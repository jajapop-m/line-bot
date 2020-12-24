class LinebotController < ApplicationController
  require 'line/bot'  # gem 'line-bot-api'

  # callbackアクションのCSRFトークン認証を無効
  protect_from_forgery :except => [:callback]

  def client
    @client ||= Line::Bot::Client.new { |config|
      config.channel_secret = ENV["LINE_CHANNEL_SECRET"]
      config.channel_token = ENV["LINE_CHANNEL_TOKEN"]
    }
  end

  def callback

    body = request.body.read

    signature = request.env['HTTP_X_LINE_SIGNATURE']
    unless client.validate_signature(body, signature)
      head :bad_request
    end

    events = client.parse_events_from(body)

    events.each do |event|
      case event
      when Line::Bot::Event::Message
        handle_message(event)
      when Line::Bot::Evnet::Follow
        messages = [
          "友達登録",
          "ありがとうございます！"
        ]
        reply_text(event, messages)
      end
    end

    head :ok
  end

  def handle_message(event)
    case event.type
    when Line::Bot::Event::MessageType::Text

      if event.message['text'].include?("好き")
        response = "いひひ"
      elsif event.message["text"].include?("行ってきます")
        response = "はーい"
      elsif event.message['text'].include?("おはよう")
        response = "おはようございます"
      elsif event.message['text'].include?("暇")
        response = "暇？"
      else
        response = event.message['text']
        response << "??"
        response = [response, "そうなのね"]
      end

      reply_text(event, response)
    end
  end

  def reply_text(event, texts)
    texts = [texts] if texts.is_a?(String)
    client.reply_message(
      event['replyToken'],
      texts.map { |text| {type: 'text', text: text} }
    )
  end
end
