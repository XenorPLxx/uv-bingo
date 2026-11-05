module Admin
  class EventsController < ApplicationController
    before_action :require_admin
    before_action :set_event, except: [ :index, :new, :create ]

    def index
      @events = Event.order(created_at: :desc)
    end

    def new
      @event = Event.new(opens_at: 1.day.from_now.change(min: 0), closes_at: 8.days.from_now.change(min: 0))
    end

    def create
      @event = Event.new(event_params)
      Event.transaction do
        @event.save!
        audit!("create_event", @event.attributes.slice("title", "opens_at", "closes_at", "rehearsal"))
      end
      redirect_to admin_event_path(@event), notice: "Wydarzenie utworzone."
    end

    def show
      @counts = @event.votes.group(:option_id).count
      @options = @event.options.includes(:participant, :merged_into).sort_by { |option| [ -@counts.fetch(option.id, 0), option.id ] }
      @merge_options = @options.reject { |option| option.disqualified_at || option.merged_into_id }
      @audits = @event.audit_entries.includes(:participant).order(created_at: :desc).limit(100)
    end

    def deletion
      prepare_deletion
    end

    def destroy
      EventDeletion.call(event: @event, confirmation: params[:confirmation])
      Rails.logger.info("Event deleted: event_id=#{@event.id} participant_id=#{current_participant.id}")
      @event.broadcast_update!
      redirect_to admin_root_path, notice: "Wydarzenie zostało usunięte.", status: :see_other
    rescue Voting::Invalid => error
      @deletion_error = error.message
      prepare_deletion
      render :deletion, status: :unprocessable_entity
    end

    def update
      @event.with_lock do
        raise Voting::Invalid, "Ustawienia zostały zamknięte po losowaniu." if @event.draw
        before = @event.attributes.slice("title", "description", "opens_at", "closes_at")
        @event.update!(event_params.except(:slug, :rehearsal))
        audit!("settings", { before: before, after: @event.attributes.slice(*before.keys) })
        @event.increment!(:revision)
      end
      @event.broadcast_update!
      redirect_to admin_event_path(@event), notice: "Ustawienia zapisane."
    end

    def draw
      BoardDraw.call(event: @event, admin: current_participant)
      @event.broadcast_update!
      redirect_to reveal_event_path(@event)
    end

    def transition
      @event.with_lock do
        target = params[:state]
        valid = (@event.state == "collecting" && @event.draw && target == "live") || (@event.state == "live" && target == "archived")
        raise Voting::Invalid, "Niedozwolona zmiana etapu." unless valid
        audit!("transition", { before: @event.state, after: target })
        @event.update!(state: target, revision: @event.revision + 1)
      end
      @event.broadcast_update!
      redirect_to admin_event_path(@event), notice: "Etap wydarzenia został zmieniony."
    end

    def moderate
      @event.with_lock do
        raise Voting::Invalid, "Propozycje są zamrożone po losowaniu." if @event.draw
        option = @event.options.find(params[:option_id])
        raise Voting::Invalid, "Ta propozycja została połączona z inną." if option.merged_into_id
        reason = params[:reason].to_s.strip
        raise Voting::Invalid, "Podaj powód moderacji (maks. 200 znaków)." unless reason.length.between?(3, 200)
        before = option.attributes.slice("text", "disqualified_at")
        case params[:operation]
        when "disqualify" then option.update!(disqualified_at: Time.current, moderation_reason: reason)
        when "restore" then option.update!(disqualified_at: nil, moderation_reason: reason)
        when "correct" then option.update!(text: params[:text], moderation_reason: reason)
        else raise Voting::Invalid, "Nieznana operacja."
        end
        audit!("moderate", { option_id: option.id, before: before, after: option.attributes.slice(*before.keys), reason: reason })
        @event.increment!(:revision)
      end
      @event.broadcast_update!
      redirect_to admin_event_path(@event, anchor: "moderation"), notice: "Zmiana zapisana. Uczestnicy mogą cofnąć swoje głosy do końca głosowania."
    end

    def merge
      result = OptionMerge.call(event: @event, admin: current_participant, source_id: params[:source_id], target_id: params[:target_id], reason: params[:reason])
      @event.broadcast_update!
      redirect_to admin_event_path(@event, anchor: "moderation"), notice: "Propozycje połączone. Przeniesione głosy: #{result[:transferred_votes]}. Zwrócone głosy: #{result[:returned_votes]}.", status: :see_other
    end

    def mark
      cell = @event.cells.find(params[:cell_id])
      BoardActions.mark!(cell: cell, admin: current_participant, mark: params[:mark], revision: params.require(:revision))
      @event.reload.broadcast_update!
      board_action_response("Oznaczenie zapisane.")
    end

    private

    def prepare_deletion
      @deletion_counts = {
        "Propozycje" => @event.options.count,
        "Głosy" => @event.votes.count,
        "Losowania" => Draw.where(event: @event).count,
        "Pola planszy" => @event.cells.count,
        "Sugestie oznaczeń" => Proposal.where(cell_id: @event.cells.select(:id)).count,
        "Wpisy w historii" => @event.audit_entries.count
      }
    end

    def event_params
      params.require(:event).permit(:title, :slug, :description, :opens_at, :closes_at, :rehearsal)
    end

    def audit!(action, details)
      @event.audit_entries.create!(participant: current_participant, action: action, details: details)
    end
  end
end
