# -*- encoding: utf-8 -*-

require 'uri'
require 'json'
require 'base64'
require 'rest_client'
require 'qiniu/rs/exceptions'

module Qiniu
  module RS
    module Utils extend self

      def urlsafe_base64_encode content
        Base64.encode64(content).strip.gsub('+', '-').gsub('/','_').gsub(/\r?\n/, '')
      end

      def urlsafe_base64_decode encoded_content
        Base64.decode64 encoded_content.gsub('_','/').gsub('-', '+')
      end

      def encode_entry_uri(bucket, key)
        entry_uri = bucket + ':' + key
        urlsafe_base64_encode(entry_uri)
      end

      def safe_json_parse(data)
        JSON.parse(data)
      rescue JSON::ParserError
        {}
      end

      def send_request_with url, data = nil, options = {}
        options[:method] = Config.settings[:method] unless options[:method]
        options[:content_type] = Config.settings[:content_type] unless options[:content_type]
        header_options = {
          :accept => :json,
          :user_agent => Config.settings[:user_agent]
        }
        header_options.merge!('Authorization' => "Bearer #{options[:access_token]}") if options[:access_token]
        case options[:method]
        when :get
          response = RestClient.get url, header_options
        when :post
          header_options.merge!(:content_type => options[:content_type])
          response = RestClient.post url, data, header_options
        end
        code = response.respond_to?(:code) ? response.code.to_i : 0
        if code != 200
          raise RequestFailed.new(response)
        else
          data = {}
          body = response.respond_to?(:body) ? response.body : {}
          data = safe_json_parse(body) unless body.empty?
        end
        [code, data]
      end

      def http_request url, data = nil, options = {}
        retry_times = 0
        begin
          retry_times += 1
          send_request_with url, data, options
        rescue Errno::ECONNRESET => err
          if Config.settings[:auto_reconnect] && retry_times < Config.settings[:max_retry_times]
            retry
          else
            Log.logger.error err
          end
        rescue => e
          Log.logger.warn "#{e.message} => Utils.http_request('#{url}')"
          code = 0
          data = {}
          body = {}
          if e.respond_to? :response
            res = e.response
            code = res.code.to_i if res.respond_to? :code
            body = res.respond_to?(:body) ? res.body : ""
            data = safe_json_parse(body) unless body.empty?
          end
          [code, data]
        end
      end

      def upload_multipart_data(url, filepath, action_string, callback_query_string = '')
        code, data = 0, {}
        begin
          header_options = {
            :accept => :json,
            :user_agent => Config.settings[:user_agent]
          }
          post_data = {
            :file => File.new(filepath, 'rb'),
            :params => callback_query_string,
            :action => action_string,
            :multipart => true
          }
          response = RestClient.post url, post_data, header_options
          body = response.respond_to?(:body) ? response.body : ""
          data = safe_json_parse(body) unless body.empty?
          code = response.code.to_i if response.respond_to?(:code)
        rescue Errno::ECONNRESET => err
          Log.logger.error err
        rescue => e
          Log.logger.warn "#{e.message} => Utils.http_request('#{url}')"
          res = e.response
          if e.respond_to? :response
            res = e.response
            code = res.code.to_i if res.respond_to? :code
            body = res.respond_to?(:body) ? res.body : ""
            data = safe_json_parse(body) unless body.empty?
          end
        end
        [code, data]
      end

      def generate_query_string(params)
        return params if params.is_a?(String)
        total_param = params.map { |key, value| key.to_s+"="+value.to_s }
        URI.escape(total_param.join("&"))
      end

    end
  end
end
