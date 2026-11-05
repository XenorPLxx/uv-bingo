abort "This command prepares the production community trial only." unless Rails.env.production?
TrialEvents.prepare!.each do |event|
  puts "#{event.title}: /e/#{event.slug} (#{event.phase}, #{event.options.count} proposals, #{event.votes.count} votes)"
end
