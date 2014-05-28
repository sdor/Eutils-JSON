require 'uri'
require 'open-uri'
require 'nori'
require 'json'

app = lambda do |env|
  req = Rack::Request.new(env)
  resp=
  unless req.params["retmode"].nil?
     case req.params["retmode"].strip
      when '' then
        {status: 'error',message: 'retmode must be defined'}.to_json
      when 'xml' then
        begin
         open("http://eutils.ncbi.nlm.nih.gov#{req.path}?#{URI.encode_www_form(req.params)}") do |f|
           {status: 'ok', result: Nori.new(:advanced_typecasting => true).parse(f.read) }.to_json
         end
        rescue OpenURI::HTTPError => e
          {"status"=>"error","message" => e.message}.to_json
        end     
      when 'json' then
        begin
         open("http://eutils.ncbi.nlm.nih.gov#{req.path}?#{URI.encode_www_form(req.params)}") do |f|
          {status: 'ok',result: JSON.parse(f.read) }.to_json
         end
        rescue OpenURI::HTTPError => e
          {"status"=>"error","message" => e.message}.to_json
        end           
      else
        {status: 'error', message: "invalid retmode #{req.params["retmode"].strip}"}.to_json   
      end
   else 
      {status: 'error',message: 'retmode must be defined'}.to_json
   end
  [200, {"Content-Type" => "application/json", "Content-Length" => resp.length.to_s }, [resp]]  
end

run app
