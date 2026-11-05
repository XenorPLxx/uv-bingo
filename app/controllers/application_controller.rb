class ApplicationController < ActionController::Base
  helper_method :current_participant
  before_action :private_response
  rescue_from Voting::Invalid, ActiveRecord::RecordInvalid, with: :invalid_action
  rescue_from ActiveRecord::RecordNotUnique, with: :duplicate_action

  private

  def current_session
    return @current_session if defined?(@current_session)
    @current_session = Session.active.includes(:participant).find_by(id: cookies.signed[:bingo_session_id])
  end

  def current_participant = current_session&.participant

  def require_participant
    redirect_to sign_in_path, alert: "Zaloguj się przez komendę /bingo na Discordzie." unless current_participant
  end

  def require_admin
    head :forbidden unless current_participant&.admin?
  end

  def set_event
    @event = Event.find_by!(slug: params[:event_id] || params[:id])
  end

  def private_response
    response.headers["Cache-Control"] = "no-store"
  end

  def invalid_action(error)
    redirect_to(@event&.persisted? ? event_path(@event) : root_path, alert: error.message, status: :see_other)
  end

  def duplicate_action
    redirect_to(@event&.persisted? ? event_path(@event) : root_path, alert: "Ta propozycja lub głos już istnieje. Nie pobrano dodatkowego głosu.", status: :see_other)
  end
end
