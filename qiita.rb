# -*- coding: utf-8 -*-
require 'yaml'
require 'pp'
require 'net/http'
require 'net/https'
require 'json'
require 'pit'

QiitaDir = "~/qiita"
QiitaLatest = "#{QiitaDir}/latest"

class Qiita < Thor
  include Thor::Actions

  desc "new", "新規エントリを作成してエディタで開く"
  def new
    file_path = make_entry_file
    edit_and_upload(file_path)
  end

  desc "edit", "ファイル名を指定してエントリを編集する。指定なしなら直前に編集したエントリ"
  def edit(file_path=nil)
    file_path = File.read(File.expand_path(QiitaLatest)).chomp unless file_path
    edit_and_upload(file_path)
  end

  no_commands do
    def make_entry_file
      qiita_dir = QiitaDir
      now = Time.now
      file_title = now.strftime("%Y-%m-%d-%H%M%S")
      year = now.strftime("%Y")
      month = now.strftime("%m")
      sep = "---"
      body = <<EOS
#{sep}
uuid: 
title: 
tags:
- name: 
private: true
#{sep}
EOS
      file_path = "#{qiita_dir}/#{year}/#{month}/#{file_title}.md"
      create_file file_path, body
      file_path
    end

    def qiita_agent
      config = Pit.get("qiita",:require=>{
                         "user" => "user id",
                         "pass" => "password"
                       })
      agent = QiitaAPI.new
      agent.auth(config["user"],config["pass"])
      agent
    end

    def edit_and_upload(file_path)
      system "#{ENV["EDITOR"]} #{file_path}"
      save_latest(file_path)
      puts "edit done"
      if yes?("#{file_path} upload? (y/N)")
        upload(file_path)
        puts "uploaded"
      end
    end

    def upload(file_path)
      path = File.expand_path(file_path)
      str = File.read(path)
      ar = str.split("---\n")
      yaml_str = ar[1]
      body = ar[2]
      config = YAML.load(yaml_str)
      puts yaml_str
      pp config
      config["body"] = body
      qa = qiita_agent
      
      unless config["uuid"]
        result = qa.post_entry(config)
        config["uuid"] = result["uuid"]
        config.delete("body")
        yaml_str = config.to_yaml
        File.open(path,"w") do |f|
          f.puts yaml_str
          f.puts "---"
          f.puts body
        end
      else
        qa.put_entry(config)
      end

    end

    def save_latest(file_path)
      open(File.expand_path(QiitaLatest),"w") do |f|
        f.puts file_path
      end
    end
  end
end

class QiitaAPI

  ### JSON HTTPS

  def http_setup(url_str)
    url = URI.parse(url_str)
    http = Net::HTTP.new(url.host,url.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    # http.set_debug_output $stderr
    [url,http]
  end

  def get(url_str)
    url, http = http_setup(url_str)
    res = http.get(url.request_uri)
    JSON.parse(res.body)
  end

  def post(url_str,data)
    url, http = http_setup(url_str)
    json_str = JSON.generate(data)
    res = http.post(url.request_uri,
                    json_str,{'Content-Type' =>'application/json'})
    JSON.parse(res.body)
  end
  
  def put(url_str,data)
    url, http = http_setup(url_str)
    json_str = JSON.generate(data)
    res = http.put(url.request_uri,
                   json_str,{'Content-Type' =>'application/json'})
    JSON.parse(res.body)
  end

  ### main

  def initialize
    @base_url = 'https://qiita.com/api/v1'
  end

  def auth?
    @token != nil
  end

  def auth(user,pass)
    r = post("#{@base_url}/auth",{url_name: user,password: pass})
    @token = r["token"]
  end

  def make_url(child_path)
    path = "#{@base_url}/#{child_path}"
    unless auth?
      path
    else
      "#{path}?token=#{@token}"
    end
  end

  ### methods

  def rate_limit
    get(make_url('rate_limit'))
  end

  def user
    raise "require auth" unless auth?
    get(make_url('user'))
  end

  def users(name)
    get(make_url("users/#{name}"))
  end

  def items
    raise "require auth" unless auth?
    get(make_url('items'))
  end

  def post_entry(data)
    raise "require auth" unless auth?
    post(make_url("items"),data)
  end
  
  def put_entry(data)
    raise "require auth" unless auth?
    uuid = data["uuid"]
    put(make_url("items/#{uuid}"),data)
  end
end
