class VotesController < ApplicationController
  before_action :require_participant
  before_action :set_event

  def create
    Voting.cast!(event: @event, participant: current_participant, option_id: params[:option_id])
    redirect_to event_path(@event, anchor: "options"), notice: "Głos zapisany. Pozostało: #{current_participant.votes_remaining(@event)} z 5."
  end

  def destroy
    Voting.withdraw!(event: @event, participant: current_participant, vote_id: params[:id])
    redirect_to event_path(@event, anchor: "options"), notice: "Głos cofnięty. Propozycja zostaje. Pozostało: #{current_participant.votes_remaining(@event)} z 5.", status: :see_other
  end
end
