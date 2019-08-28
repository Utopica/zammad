require 'test_helper'
require 'rexml/document'
require 'webmock/minitest'

class QuepasaTest < ActionDispatch::IntegrationTest

  token = 'valid_token'
  api_url = 'https://quepasa.foo/v1'
  bot_number = '15555555552'
  bot_id = '129f1757-e706-452e-aa1c-4994a95e1092'
  customer_number = '15555555551'
  incoming_message_id = 'AAAAAAAAAAAAAAAAAAAA'
  outgoing_message_id = 'BBBBBBBBBBBBB'
  group_id = Group.find_by(name: 'Users').id
  channel = nil

  setup do
    @headers = { 'ACCEPT' => 'application/json', 'CONTENT_TYPE' => 'application/json' }
    # configure quepasa channel
    UserInfo.current_user_id = 1
    # try check with valid token
    stub_request(:get, "#{api_url}/bot/#{token}")
        .to_return(status: 200, body: "{
  \"id\": \"129f1757-e706-452e-aa1c-4994a95e1092\",
  \"number\": \"#{bot_number}\",
  \"user_id\": \"845ae4d0-f2c3-5342-91a2-5b45cb8db57c\",
  \"token\": \"#{token}\",
  \"is_verified\": true,
  \"created_at\": \"2018-11-02T11:36:24.273Z\",
  \"updated_at\": \"2018-11-02T11:36:24.273Z\"
}", headers: {})
    Quepasa.create_or_update_channel(api_url, token, {group_id: group_id, welcome: 'hi!' })

    channel = Quepasa.bot_by_bot_id(bot_id)

    assert(channel, 'Quepasa channel created')
  end

  teardown do
    Channel.where(area: 'Quepasa::Account').destroy_all
  end

  test 'check token validity works' do
    # try check with invalid token
    stub_request(:get, "#{api_url}/bot/not_existing")
        .to_return(status: 404, body: '{"ok":false,"error_code":404,"description":"Not Found"}', headers: {})

    assert_raises(RuntimeError) do
      Quepasa.check_token(api_url, 'not_existing')
    end

    # try check with valid token
    stub_request(:get, "#{api_url}/bot/#{token}")
        .to_return(status: 200, body: "{
  \"id\": \"129f1757-e706-452e-aa1c-4994a95e1092\",
  \"number\": \"#{bot_number}\",
  \"user_id\": \"845ae4d0-f2c3-5342-91a2-5b45cb8db57c\",
  \"token\": \"#{token}\",
  \"is_verified\": true,
  \"created_at\": \"2018-11-02T11:36:24.273Z\",
  \"updated_at\": \"2018-11-02T11:36:24.273Z\"
}", headers: {})

    bot = Quepasa.check_token(api_url, token)
    assert_equal(bot_number, bot['number'])
  end

  test 'inbound new ticket and reply' do
    Ticket.destroy_all

    # create the inbound whatsapp message, and stub the API call
    inbound_response = read_message('message1_inbound1_response')
    inbound_message = JSON.parse(inbound_response)['messages'][0]
    stub_request(:get, "#{api_url}/bot/#{token}/receive")
        .to_return(status: 200, body: inbound_response, headers: {})

    # stub the API response for sending a message
    outbound_content = JSON.parse(read_message('message1_outbound1_content'))
    outbound_response = read_message('message1_outbound1_response')
    stub_request(:post, "#{api_url}/bot/#{token}/send")
        .with(body: outbound_content)
        .to_return(status: 200, body: outbound_response, headers: {})


    # Fetch the messages from the channel, hitting our inbound stub
    Channel.fetch

    # check if follow up article has been created
    article = Ticket::Article.find_by(message_id: incoming_message_id)

    assert(article, "article message '#{incoming_message_id}' imported")
    assert_equal("#{inbound_message['name']} ", article.from, 'ticket article from')
    assert_equal(bot_number, article.to, 'ticket article to')
    assert_equal(incoming_message_id, article.message_id, 'ticket article inbound message_id')
    assert_equal(1, article.ticket.articles.count, 'ticket article inbound count')
    assert_equal(inbound_message['body'], article.body, 'ticket article inbound body')
    assert_equal('new', article.ticket.reload.state.name)


    # check customer
    customer = article.ticket.customer
    assert_equal(inbound_message['name'], customer.firstname)
    assert_equal(customer_number, customer.login)
    assert_equal(customer_number, customer.mobile)
    assert(customer.note.include?("QuePasa #{customer_number}"))

    ticket = article.ticket

    channel = Channel.find(channel.id)
    # assert_equal('', channel.last_log_out)
    # assert_equal('ok', channel.status_out)
    assert_equal('', channel.last_log_in)
    assert_equal('ok', channel.status_in)

    # send the reply
    reply_text = 'Yes! I can help.'
    article = Ticket::Article.create!(
      ticket_id:     ticket.id,
      body:          reply_text,
      type:          Ticket::Article::Type.find_by(name: 'quepasa personal-message'),
      sender:        Ticket::Article::Sender.find_by(name: 'Agent'),
      internal:      false,
      updated_by_id: 1,
      created_by_id: 1,
    )

    # Start the worker to send our outgoing message to the oubound stub
    Scheduler.worker(true)
    assert_equal('open', ticket.reload.state.name)
    article = Ticket::Article.find(article.id)
    assert(article, "article message '#{incoming_message_id}' imported")
    assert_equal(2, article.ticket.articles.count, 'ticket article outbound count')
    assert_equal(reply_text, article.body, 'ticket article outbound body')
    assert_equal(outgoing_message_id, article.message_id, 'ticket article outbound message id')
    assert_equal(customer_number, article.to, 'ticket article to')
    assert_equal(bot_number, article.from, 'ticket article to')


  end

  def read_message(file)
    File.read(Rails.root.join('test', 'data', 'quepasa', "#{file}.json"))
  end
end
