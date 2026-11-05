class EventsController < ApplicationController
  before_action :set_event, except: :index

  def index
    flash.now[:notice] = "Wydarzenie zostało usunięte." if params[:removed] == "1"
    @events = Event.order(created_at: :desc)
    @event = @events.where.not(state: "archived").first || @events.first
    if @event
      prepare_event
      render :show
    else
      render :empty
    end
  end

  def show
    prepare_event
  end

  def presentation
    raise ActiveRecord::RecordNotFound unless @event.draw
    @presentation = true
    render :board
  end

  def reveal
    raise ActiveRecord::RecordNotFound unless @event.draw
    @presentation = true
    render :reveal
  end

  def state
    response.headers["Cache-Control"] = "no-store"
    data = { phase: @event.phase, revision: @event.revision }
    changed = params[:refresh] == "1" || params[:revision] != @event.revision.to_s || params[:phase] != @event.phase
    if @event.draw && changed
      @presentation = params[:presentation] == "1"
      data[:html] = render_to_string(partial: "events/board", formats: [ :html ])
    elsif !@event.draw && changed
      prepare_voting
      data[:voting] = {
        options: render_to_string(partial: "events/voting_options", formats: [ :html ]),
        ballot: render_to_string(partial: "events/ballot", formats: [ :html ]),
        add_option: render_to_string(partial: "events/add_option", formats: [ :html ]),
        schedule: render_to_string(partial: "events/voting_schedule", formats: [ :html ]),
        can_add: @can_add_option
      }
    end
    render json: data
  end

  def draw_record
    draw = @event.draw || raise(ActiveRecord::RecordNotFound)
    send_data JSON.pretty_generate(draw.as_json(only: [ :algorithm, :seed, :snapshot, :snapshot_digest, :result, :created_at ])),
      type: "application/json", disposition: "attachment", filename: "#{@event.slug}-losowanie.json"
  end

  private

  def prepare_event
    @events = Event.includes(:draw).order(created_at: :desc)
    prepare_voting
  end

  def prepare_voting
    @options = @event.options.eligible
    @query = params[:q].to_s.first(100)
    @options = @options.where("text ILIKE ?", "%#{Option.sanitize_sql_like(@query)}%") if @query.present?
    @counts = @event.votes.group(:option_id).count
    @options = @options.sort_by { |option| [ -@counts.fetch(option.id, 0), option.created_at, option.id ] }
    @remaining = current_participant&.votes_remaining(@event)
    @authored_option_count = current_participant ? @event.options.where(participant: current_participant).count : 0
    @can_add_option = @event.voting_open? && current_participant.present? && @remaining.positive? && @authored_option_count < Option::PER_PARTICIPANT_LIMIT
    @my_votes = current_participant&.votes&.where(event: @event)&.includes(:option)&.order(:slot)
    @votes_by_option = @my_votes&.index_by(&:option_id) || {}
  end
end
