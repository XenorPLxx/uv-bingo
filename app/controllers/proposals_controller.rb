class ProposalsController < ApplicationController
  before_action :require_participant
  before_action :set_event
  rate_limit to: 30, within: 1.minute, by: -> { current_participant.id }

  def create
    cell = @event.cells.find(params[:cell_id])
    BoardActions.propose!(cell: cell, participant: current_participant, mark: params[:mark], revision: params.require(:revision))
    @event.reload.broadcast_update!
    board_action_response(params[:mark] == "blank" ? "Twoja propozycja oznaczenia została cofnięta." : "Twoja propozycja oznaczenia została zapisana.")
  end
end
