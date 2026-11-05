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
    return if current_participant
    message = "Zaloguj się przez komendę /bingo na Discordzie."
    respond_to do |format|
      format.json { render json: { error: message }, status: :unauthorized }
      format.html { redirect_to sign_in_path, alert: message }
    end
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
    respond_to do |format|
      format.json { render json: { error: error.message }, status: :unprocessable_entity }
      format.html { redirect_to(@event&.persisted? ? board_return_path : root_path, alert: error.message, status: :see_other) }
    end
  end

  def board_action_response(message)
    respond_to do |format|
      format.json { render json: { message: message } }
      format.html { redirect_to board_return_path, notice: message, status: :see_other }
    end
  end

  def board_return_path
    params[:presentation] == "1" && @event.draw ? presentation_event_path(@event) : event_path(@event)
  end

  def duplicate_action
    redirect_to(@event&.persisted? ? event_path(@event) : root_path, alert: "Ta propozycja lub głos już istnieje. Nie pobrano dodatkowego głosu.", status: :see_other)
  end
end
