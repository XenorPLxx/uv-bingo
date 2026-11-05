class SessionsController < ApplicationController
  rate_limit to: 30, within: 1.minute, only: [ :capture, :create ]

  def new
  end

  def capture
    response.headers["Cache-Control"] = "no-store"
    token = LoginToken.find_usable(params[:token])
    if token
      session[:pending_login_token] = params[:token]
      redirect_to confirm_login_path
    else
      redirect_to sign_in_path, alert: "Link wygasł lub został wykorzystany. Użyj komendy /bingo ponownie."
    end
  end

  def confirm
    @token = LoginToken.find_usable(session[:pending_login_token])
    redirect_to sign_in_path, alert: "Użyj komendy /bingo, aby się zalogować." unless @token
  end

  def create
    token = LoginToken.find_usable(session[:pending_login_token])
    raise Voting::Invalid, "Link wygasł. Użyj komendy /bingo ponownie." unless token
    login_session = token.with_lock do
      raise Voting::Invalid, "Link został już wykorzystany lub wygasł." if token.consumed_at || token.expires_at <= Time.current
      token.update!(consumed_at: Time.current)
      Session.create!(participant: token.participant, expires_at: 30.days.from_now)
    end
    current_session&.destroy!
    reset_session
    cookies.signed[:bingo_session_id] = { value: login_session.id, expires: login_session.expires_at,
      httponly: true, secure: !Rails.env.local?, same_site: :lax }
    redirect_to root_path, notice: "Zalogowano."
  end

  def destroy
    current_session&.destroy!
    cookies.delete(:bingo_session_id)
    reset_session
    redirect_to root_path, notice: "Wylogowano. Twoje głosy są zapisane."
  end
end
