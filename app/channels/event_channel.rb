class EventChannel < ApplicationCable::Channel
  # Open pages per event. Production runs a single Puma process, so the counts live in its memory;
  # after a restart every client resubscribes and the counts rebuild themselves.
  @viewers = Hash.new(0)
  @lock = Mutex.new

  class << self
    def viewers(event_id) = @lock.synchronize { @viewers[event_id] }

    # Read and send under the same lock so concurrent deliveries cannot send an older count last.
    def with_viewers(event_id, &block)
      @lock.synchronize { block.call(@viewers[event_id]) }
    end

    def change_viewers(event_id, delta)
      @lock.synchronize do
        count = [ @viewers[event_id] + delta, 0 ].max
        count.zero? ? @viewers.delete(event_id) : @viewers[event_id] = count
        count
      end
    end
  end

  def subscribed
    @event_id = Event.where(id: params[:event_id]).pick(:id)
    return reject unless @event_id
    stream_from "event:#{@event_id}", coder: ActiveSupport::JSON, &method(:receive_update)
    @counted = true
    broadcast_viewers(self.class.change_viewers(@event_id, 1))
  end

  def unsubscribed
    return unless @counted
    @counted = false
    broadcast_viewers(self.class.change_viewers(@event_id, -1))
  end

  # Requested after the stream is confirmed: the join broadcast may precede registration.
  def viewer_count
    self.class.with_viewers(@event_id) { |count| transmit({ viewers: count }) }
  end

  private

  def receive_update(data)
    # Broadcasts can arrive out of order across workers; send the current count, not the snapshot.
    data.key?("viewers") ? viewer_count : transmit(data)
  end

  def broadcast_viewers(count)
    ActionCable.server.broadcast("event:#{@event_id}", { viewers: count })
  end
end
