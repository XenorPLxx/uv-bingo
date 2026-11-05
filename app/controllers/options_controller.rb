class OptionsController < ApplicationController
  before_action :require_participant
  before_action :set_event
  rate_limit to: 10, within: 1.minute, by: -> { current_participant.id }

  def create
    Voting.cast!(event: @event, participant: current_participant, text: params[:text])
    voting_action_response("Propozycja dodana z Twoim głosem. Pozostało: #{current_participant.votes_remaining(@event)} z 5.")
  end
end
