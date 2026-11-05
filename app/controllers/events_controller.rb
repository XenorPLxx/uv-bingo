class EventsController < ApplicationController
  before_action :set_event, except: :index

  def index
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
    if @event.draw
      @presentation = params[:presentation] == "1"
      data[:html] = render_to_string(partial: "events/board", formats: [ :html ])
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
    @options = @event.options.eligible.order(:created_at)
    @query = params[:q].to_s.first(100)
    @options = @options.where("text ILIKE ?", "%#{Option.sanitize_sql_like(@query)}%") if @query.present?
    @voted_ids = current_participant ? current_participant.votes.where(event: @event).pluck(:option_id) : []
    @remaining = current_participant&.votes_remaining(@event)
    @counts = @event.votes.group(:option_id).count if %w[closed drawn live archived].include?(@event.phase)
    @my_votes = current_participant&.votes&.where(event: @event)&.includes(:option)&.order(:slot)
  end
end
