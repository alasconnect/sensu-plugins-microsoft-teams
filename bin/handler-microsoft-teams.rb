#!/usr/bin/env ruby
# frozen_string_literal: true

# Copyright 2017 Jose Gaspar and contributors.
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.
#
# In order to use this plugin, you must first configure an incoming webhook
# integration in Microsoft Teams. You can create the required webhook by
# visiting
# https://docs.microsoft.com/en-us/outlook/actionable-messages/actionable-messages-via-connectors#sending-actionable-messages-via-office-365-connectors
#
# After you configure your webhook, you'll need the webhook URL from the integration.

require 'sensu-handler'
require 'json'
require 'erubis'

class MicrosoftTeams < Sensu::Handler
  option :webhook_url,
          description: 'Microsoft Teams Webhook URL'
          short: '-w URL',
          long: '--webhook URL'

  def incident_key
      @event['client']['name'] + '/' + @event['check']['name']
  end

  def handle
      description = @event['check']['notification'] || build_description
      post_data("#{incident_key}: #{description}")
  end

  def build_description
    template =  '<%=
                 [
                   @event["check"]["output"].gsub(\'"\', \'\\"\'),
                   @event["client"]["address"],
                   @event["client"]["subscriptions"].join(",")
                 ].join(" : ")
                 %>
                 '
    eruby = Erubis::Eruby.new(template)
    eruby.result(binding)
  end

  def post_data(body)
    uri = URI(config[:webhook_url])
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new("#{uri.path}?#{uri.query}", 'Content-Type' => 'application/json')

    req.body = payload(body).to_json

    response = http.request(req)
    verify_response(response)
  end

  def verify_response(response)
    case response
    when Net::HTTPSuccess
      true
    else
      raise response.error!
    end
  end

  def payload(notice)
    {
      themeColor: color,
      text: "#{@event['client']['address']} - #{translate_status}",
      sections: [{
        activityImage: 'https://raw.githubusercontent.com/sensu/sensu-logo/master/sensu1_flat%20white%20bg_png.png',
        text: [notice].compact.join(' ')
      }]
    }
  end

  def color
    color = {
      0 => '#36a64f',
      1 => '#FFCC00',
      2 => '#FF0000',
      3 => '#6600CC'
    }
    # a script can return any error code it feels like we should not assume
    # that it will always be 0,1,2,3 even if that is the sensu (nagions)
    # specification. A couple common examples:
    # 1. A sensu server schedules a check on the instance but the command
    # executed does not exist in your `$PATH`. Shells will return a `127` status
    # code.
    # 2. Similarly a `126` is a permission denied or the command is not
    # executable.
    # Rather than adding every possible value we should just treat any non spec
    # designated status code as `unknown`s.
    begin
      color.fetch(check_status.to_i)
    rescue KeyError
      color.fetch(3)
    end
  end

  def check_status
    @event['check']['status']
  end

  def translate_status
    status = {
      0 => :OK,
      1 => :WARNING,
      2 => :CRITICAL,
      3 => :UNKNOWN
    }
    begin
      status[check_status.to_i]
    # handle any non standard check status as `unknown`
    rescue KeyError
      status.fetch(3)
    end
  end
end
