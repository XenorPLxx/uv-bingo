class OptionsController < ApplicationController
  before_action :require_participant
  before_action :set_event

  def create
    Voting.cast!(event: @event, participant: current_participant, text: params[:text])
    redirect_to event_path(@event, anchor: "options"), notice: "Propozycja dodana z Twoim głosem. Pozostało: #{current_participant.votes_remaining(@event)} z 5."
  end
end
