class SyncGoogleCalendarServices
  def initialize client, service, current_user
    @client = client
    @service = service
    @current_user = current_user
    @calendars = Calendar.all
    @default_calendar = current_user.calendars.find_by is_default: true
  end

  def pull_events
    results = @client.execute(api_method: @service.events.list,
      parameters: {"calendarId": @current_user.google_calendar_id})
    events = results.data.items.select do |event|
      event.status == Settings.status_confirmed
    end
    events.each{|event| create_event event}
  end

  private
  def extract_event_title title
    calendar_name, event_title = title.split(": ").each{|string| string.capitalize!}
    calendar = @calendars.find_by name: calendar_name
    calendar_id = calendar.present? ? calendar.id : @default_calendar.id

    return calendar_id, event_title
  end

  def create_event event_sync
    calendar_id, event_title = extract_event_title event_sync.summary
    event = Event.new
    event.title = event_title
    event.description = event_sync.description
    event.user_id = @current_user.id
    event.calendar_id = calendar_id
    if event_sync.recurring_event_id.present?
      event.google_event_id = event_sync.recurringEventId
    else
      event.google_event_id = event_sync.id
    end
    set_date_time_for_event event_sync, event
    event.save
  end

  def set_date_time_for_event event_sync, event
    if event_sync.start.date.present?
      event.all_day = true
      event.start_date = event.start_repeat =
        event_sync.start.date.to_datetime.beginning_of_day
        .strftime Settings.event.format_datetime
      event.finish_date = event_sync.end.date.to_datetime
        .end_of_day.strftime Settings.event.format_datetime
      if event_sync.recurring_event_id.present?
        event.delete_only!
        event.exception_time = event.start_date
      end
    else
      event.start_date = event.start_repeat =
        event_sync.start.dateTime.strftime Settings.event.format_datetime
      event.finish_date =
        event_sync.end.dateTime.strftime Settings.event.format_datetime
      if event_sync.recurring_event_id.present?
        event.delete_only!
        event.exception_time = event.start_date
      end
    end
  end
end
