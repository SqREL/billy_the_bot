require 'spec_helper'
require 'rack/test'
require_relative '../web_app'

RSpec.describe 'Web Application' do
  include Rack::Test::Methods

  let(:admin_username) { 'admin' }
  let(:admin_password) { 'admin123' }

  def app
    Sinatra::Application
  end

  before do
    # Clear sessions before each test
    env 'rack.session', {}
  end

  def login_as_admin
    post '/login', username: admin_username, password: admin_password
  end

  describe 'Authentication' do
    describe 'GET /login' do
      it 'shows login page' do
        get '/login'
        expect(last_response).to be_ok
        expect(last_response.body).to include('Login')
      end
    end

    describe 'POST /login' do
      context 'with valid credentials' do
        it 'authenticates and redirects to dashboard' do
          post '/login', username: admin_username, password: admin_password
          expect(last_response.status).to eq(302)
          expect(last_response.location).to end_with('/')
        end

        it 'creates admin session record' do
          expect do
            post '/login', username: admin_username, password: admin_password
          end.to change { AdminSession.count }.by(1)
        end
      end

      context 'with invalid credentials' do
        it 'shows error message' do
          post '/login', username: 'wrong', password: 'wrong'
          expect(last_response).to be_ok
          expect(last_response.body).to include('Invalid credentials')
        end

        it 'does not create admin session' do
          expect do
            post '/login', username: 'wrong', password: 'wrong'
          end.not_to(change { AdminSession.count })
        end
      end
    end

    describe 'GET /logout' do
      let!(:session_record) do
        AdminSession.create!(session_id: '123', username: admin_username, ip_address: '127.0.0.1',
                             expires_at: 1.day.from_now)
      end

      before do
        login_as_admin
      end

      it 'clears session and redirects to login' do
        get '/logout'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to end_with('/login')
        expect(session).to be_empty
      end

      xit 'deletes admin session record' do
        expect { get '/logout' }.to change { AdminSession.count }.by(-1)
      end
    end
  end

  describe 'Protected Routes' do
    context 'without authentication' do
      it 'redirects to login page' do
        get '/'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to end_with('/login')
      end

      it 'redirects users page to login' do
        get '/users'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to end_with('/login')
      end
    end

    context 'with authentication' do
      before do
        login_as_admin
      end

      describe 'GET /' do
        it 'shows dashboard page' do
          get '/'
          expect(last_response).to be_ok
          expect(last_response.body).to include('Dashboard')
        end

        xit 'extends session expiry' do
          old_expiry = session[:expires_at]
          sleep(1) # Ensure time difference
          get '/'
          expect(session[:expires_at]).to be > old_expiry
        end
      end

      describe 'GET /users' do
        let!(:user) { create(:user, username: 'testuser') }

        it 'shows users page' do
          get '/users'
          expect(last_response).to be_ok
          expect(last_response.body).to include('Users')
        end

        it 'supports search functionality' do
          get '/users', search: 'testuser'
          expect(last_response).to be_ok
          expect(last_response.body).to include('testuser')
        end

        it 'supports pagination' do
          get '/users', page: 2
          expect(last_response).to be_ok
        end
      end
    end

    context 'with expired session' do
      before do
        login_as_admin
        session[:expires_at] = 1.hour.ago.to_i
      end

      xit 'redirects to login' do
        get '/'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to end_with('/login')
      end
    end
  end

  describe 'Helper Methods' do
    describe '#authenticated?' do
      it 'returns true for valid session' do
        login_as_admin
        expect(last_request.env['rack.session'][:admin_authenticated]).to be true
        expect(last_request.env['rack.session'][:expires_at]).to be > Time.now.to_i
      end

      it 'returns false for missing authentication' do
        get '/'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to end_with('/login')
      end

      xit 'returns false for expired session' do
        login_as_admin
        session[:expires_at] = 1.hour.ago.to_i
        get '/'
        expect(last_response.status).to eq(302)
        expect(last_response.location).to end_with('/login')
      end
    end

    describe '#extend_session!' do
      xit 'updates session expiry' do
        login_as_admin
        old_expiry = session[:expires_at]
        sleep(1) # Ensure time difference
        get '/'
        expect(session[:expires_at]).to be > old_expiry
      end
    end
  end
end
