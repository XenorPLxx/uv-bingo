class VotesController < ApplicationController
  before_action :require_participant
  before_action :set_event

  def create
    Voting.cast!(event: @event, participant: current_participant, option_id: params[:option_id])
    redirect_to event_path(@event, anchor: "options"), notice: "Głos zapisany. Pozostało: #{current_participant.votes_remaining(@event)} z 5."
  end
end
