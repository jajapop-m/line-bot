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
      when Line::Bot::Event::Follow
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
      message = event.message['text']

      if message.include?("好き")
        response = "いひひ"
      elsif message.include?("行ってきます")
        response = "はーい"
      elsif message.include?("おはよう")
        response = "おはようございます"
      elsif message.include?("暇")
        response = "暇？"
      elsif message == 'confirm'
        reply_content(event, {
          type: 'template',
          altText: 'Confirm alt text',
          template: {
            type: 'confirm',
            text: '「はい」か「いいえ」を選んでください',
            actions: [
              { label: 'はい', type: 'message', text: 'はい' },
              { label: 'いいえ', type: 'message', text: 'いいえ' },
            ],
          }
        })
      elsif message == 'carousel'
        reply_content(event, {
          type: 'template',
          altText: 'Carousel alt text',
          template: {
            type: 'carousel',
            columns: [
              {
                title: 'hoge',
                text: 'fuga',
                actions: [
                  { label: 'Go to line.me', type: 'uri', uri: 'https://line.me', altUri: {desktop: 'https://line.me#desktop'} },
                  { label: 'Send postback', type: 'postback', data: 'hello world' },
                  { label: 'Send message', type: 'message', text: 'This is message' }
                ]
              },
              {
                title: 'Datetime Picker',
                text: 'Please select a date, time or datetime',
                actions: [
                  {
                    type: 'datetimepicker',
                    label: "Datetime",
                    data: 'action=sel',
                    mode: 'datetime',
                    initial: '2017-06-18T06:15',
                    max: '2100-12-31T23:59',
                    min: '1900-01-01T00:00'
                  },
                  {
                    type: 'datetimepicker',
                    label: "Date",
                    data: 'action=sel&only=date',
                    mode: 'date',
                    initial: '2017-06-18',
                    max: '2100-12-31',
                    min: '1900-01-01'
                  },
                  {
                    type: 'datetimepicker',
                    label: "Time",
                    data: 'action=sel&only=time',
                    mode: 'time',
                    initial: '12:15',
                    max: '23:00',
                    min: '10:00'
                  }
                ]
              }
            ]
          }
        )
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

  def reply_content(event, messages)
    res = client.reply_message(
      event['replyToken'],
      messages
    )
    logger.warn res.read_body unless Net::HTTPOK === res
    res
  end
end
