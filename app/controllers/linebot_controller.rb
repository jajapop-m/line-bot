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
        profile = client.get_profile(event['source']['userId'])
        profile = JSON.parse(profile.read_body)
        user_name = profile['displayName']
        text = <<~EOF
          #{user_name}さん、はじめまして$！
          友だち追加ありがとうございます。

          このトークからの通知を受け取らない場合は、画面右上のメニューから通知をオフにしてください。
        EOF
        pos = -1
        pos = index = text.index('$', pos+=1)
        messages = [{
          type: 'text',
          text: text,
          emojis: [
              {
                index: index,
                productId: '5ac1bfd5040ab15980c9b435',
                emojiId: '001'
              }
            ]
          },
          "特殊メッセージ一覧:",
          "confirm, carousel, push, profile"
        ]
        reply_content(event, messages)
      when Line::Bot::Event::Postback
        message = "[POSTBACK]\n#{event['postback']['data']} (#{JSON.generate(event['postback']['params'])})"
        reply_text(event, message)
      when Line::Bot::Event::Unsend
        handle_unsend(event)
      else
        reply_text(event, "event type: #{event}\nis unable to respond")
      end
    end

    head :ok
  end

  def handle_message(event)
    case event.type
    when Line::Bot::Event::MessageType::Sticker
      handle_sticker(event)
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
        })

      elsif message == 'push'
        handle_unsend(event)
      elsif message == 'profile'
        if event['source']['type'] == 'user'
          profile = client.get_profile(event['source']['userId'])
          profile = JSON.parse(profile.read_body)
          reply_text(event, [
            "Display name\n#{profile['displayName']}",
            "Status message\n#{profile['statusMessage']}"
          ])
        else
          reply_text(event, "Bot can't use profile API without user ID")
        end
      elsif message == 'emoji'
        reply_content(event, {
          type: 'text',
          text: 'Look at this: $ It\'s a LINE emoji!',
          emojis: [
            {
                index: 14,
                productId: '5ac1bfd5040ab15980c9b435',
                emojiId: '001'
            }
          ]
        })
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

  def handle_sticker(event)
    # Message API available stickers
    # https://developers.line.me/media/messaging-api/sticker_list.pdf

    package_id = event.message['packageId'].to_i
    p_id, s_id = get_random_sticker(package_id)
    messages = [{
        type: 'sticker',
        packageId: p_id,
        stickerId: s_id
      }]

    reply_content(event, messages)
  end

  def handle_unsend(event)
    source = event['source']
    id = case source['type']
    when 'user'
      source['userId']
    when 'group'
      source['groupId']
    when 'room'
      source['roomId']
    end
    client.push_message(id, {
      type: 'text',
      text: "[UNSEND]\n}"
    })
  end

  def get_random_sticker(id)
    availableStickerList = [
      ['11537',
        %[52002734 52002735 52002736 52002737 52002738 52002739 52002740 52002741 52002742 52002743
          52002744 52002745 52002746 52002747 52002748 52002749 52002750 52002751 52002752 52002753
          52002754 52002755 52002756 52002757 52002758 52002759 52002760 52002761 52002762 52002763
          52002764 52002765 52002766 52002767 52002768 52002769 52002770 52002771 52002772 52002773].split
      ],
      ['11538',
        %[51626494 51626495 51626496 51626497 51626498 51626499 51626500 51626501 51626502 51626503
          51626504 51626505 51626506 51626507 51626508 51626509 51626510 51626511 51626512 51626513
          51626514 51626515 51626516 51626517 51626518 51626519 51626520 51626521 51626522 51626523
          51626524 51626525 51626526 51626527 51626528 51626529 51626530 51626531 51626532 51626533].split
      ],
      ['11539',
        %[52114110 52114111 52114112 52114113 52114114 52114115 52114116 52114117 52114118 52114119
          52114120 52114121 52114122 52114123 52114124 52114125 52114126 52114127 52114128 52114129
          52114130 52114131 52114132 52114133 52114134 52114135 52114136 52114137 52114138 52114139
          52114140 52114141 52114142 52114143 52114144 52114145 52114146 52114147 52114148 52114149].split
      ]
    ]
    i = [0,1,2].sample unless [11537,11538,11539].include? id.to_i
    i ||= (id.to_i+1) % 3
    [availableStickerList[i][0], availableStickerList[i][1].sample]
  end
end
