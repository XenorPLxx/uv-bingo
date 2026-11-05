module Admin
  class ParticipantsController < ApplicationController
    before_action :require_admin

    def index
      @query = params[:q].to_s.strip.first(100)
      @participants = Participant.order(created_at: :desc, id: :desc)
      if @query.present?
        @participants = @participants.where("display_name ILIKE :name OR discord_id = :id", name: "%#{Participant.sanitize_sql_like(@query)}%", id: @query)
      end
      @total_count = Participant.count
      @vote_counts = Vote.group(:participant_id).count
      @event_counts = Vote.group(:participant_id).distinct.count(:event_id)
      @option_counts = Option.group(:participant_id).count
      @last_logins = LoginToken.where.not(consumed_at: nil).group(:participant_id).maximum(:consumed_at)
    end

    def show
      @participant = Participant.find(params[:id])
      @last_login = @participant.login_tokens.where.not(consumed_at: nil).maximum(:consumed_at)
      @votes_by_event = @participant.votes.includes(:option).order(:created_at, :id).group_by(&:event_id)
      @options_by_event = @participant.options.includes(:merged_into).order(:created_at, :id).group_by(&:event_id)
      @events = Event.where(id: @votes_by_event.keys | @options_by_event.keys).order(created_at: :desc)
    end
  end
end
