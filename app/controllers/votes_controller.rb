class VotesController < ApplicationController
  before_action :require_participant
  before_action :set_event

  def create
    Voting.cast!(event: @event, participant: current_participant, option_id: params[:option_id])
    voting_action_response("Głos zapisany. Pozostało: #{current_participant.votes_remaining(@event)} z 5.")
  end

  def destroy
    Voting.withdraw!(event: @event, participant: current_participant, vote_id: params[:id])
    voting_action_response("Głos cofnięty. Propozycja zostaje. Pozostało: #{current_participant.votes_remaining(@event)} z 5.")
  end
end
