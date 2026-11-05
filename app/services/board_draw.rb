class BoardDraw
  ALGORITHM = "sha256-order-v1".freeze

  # Version-independent, domain-separated random ordering for ties and positions.
  def self.arrange(snapshot, seed)
    ranked = snapshot.sort_by { |item| [ -item.fetch("votes"), key(seed, "ties", item.fetch("id")), item.fetch("id") ] }.first(25)
    center, *others = ranked
    board = others.sort_by { |item| [ key(seed, "positions", item.fetch("id")), item.fetch("id") ] }
    board.insert(12, center)
    board.map { |item| item.fetch("id") }
  end

  def self.key(seed, purpose, id)
    Digest::SHA256.hexdigest("#{ALGORITHM}:#{purpose}:#{seed}:#{id}")
  end

  def self.call(event:, admin:)
    event.with_lock do
      return event.draw if event.draw
      raise Voting::Invalid, "Poczekaj na koniec głosowania." if Time.current < event.closes_at || event.state != "collecting"
      counts = event.votes.group(:option_id).count
      snapshot = event.options.eligible.with_votes.order(:id).map { |option| { "id" => option.id, "text" => option.text, "votes" => counts.fetch(option.id, 0) } }
      raise Voting::Invalid, "Potrzeba co najmniej 25 propozycji z głosami." if snapshot.size < 25
      seed = SecureRandom.hex(32)
      result = arrange(snapshot, seed)
      draw = event.create_draw!(participant: admin, seed: seed, algorithm: ALGORITHM,
        snapshot: snapshot, snapshot_digest: Digest::SHA256.hexdigest(JSON.generate(snapshot)), result: result)
      by_id = snapshot.index_by { |item| item["id"] }
      result.each_with_index do |id, position|
        item = by_id.fetch(id)
        event.cells.create!(option_id: id, position: position, text: item["text"], votes_count: item["votes"])
      end
      event.audit_entries.create!(participant: admin, action: "draw", details: { draw_id: draw.id, digest: draw.snapshot_digest })
      event.increment!(:revision)
      draw
    end
  end
end
