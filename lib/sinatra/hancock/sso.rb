gem 'sinatra', '~>0.9.1'
require 'rack'
require 'sinatra/base'
gem 'dm-core', '~>0.9.10'
require 'dm-core'

gem 'ruby-openid', '>=2.1.2'
require File.dirname(__FILE__)+'/../../rack-openid'

module Hancock
  class Config
    cattr_accessor :sso_url

    def self.configure(&block)
      yield self
    end
  end
end

module Sinatra
  module Hancock
    module SSO
      module Helpers
        def sso_url
          ::Hancock::Config.sso_url
        end

        def absolute_url(suffix = nil)
          port_part = case request.scheme
                      when "http"
                        request.port == 80 ? "" : ":#{request.port}"
                      when "https"
                        request.port == 443 ? "" : ":#{request.port}"
                      end
          "#{request.scheme}://#{request.host}#{port_part}#{suffix}"
        end
      end

      def self.registered(app)
        app.use(Rack::OpenID)
        app.helpers Hancock::SSO::Helpers
        app.enable :sessions

        app.get '/login' do
          if contact_id = params['id']
            response['WWW-Authenticate'] = Rack::OpenID.build_header(
              :identifier => "#{sso_url}/users/#{contact_id}",
              :trust_root => absolute_url('/login')
            )
            throw :halt, [401, 'got openid?']
          elsif openid = request.env["rack.openid.response"]
            if openid.status == :success
              if contact_id = openid.display_identifier.split("/").last
                session.delete(:last_oidreq)
                session.delete('OpenID::Consumer::last_requested_endpoint')
                session.delete('OpenID::Consumer::DiscoveredServices::OpenID::Consumer::')

                session[:user_id] = contact_id
                params = openid.message.get_args("http://openid.net/extensions/sreg/1.1")
                params.each { |key, value| session[key.to_sym] = value.to_s }
                redirect '/'
              else
                raise "No contact could be found for #{openid.display_identifier}"
              end
            else
              throw :halt, [503, "Error: #{openid.status}"]
            end
          else
            redirect "#{sso_url}/login?return_to=#{absolute_url('/login')}"
          end
        end

        app.get '/logout' do
          session.clear
          redirect "#{sso_url}/logout"
        end
      end
    end
  end
  register Hancock::SSO
end
