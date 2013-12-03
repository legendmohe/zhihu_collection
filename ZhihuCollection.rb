# encoding: UTF-8
require 'fileutils'
require "net/http"
require "uri"
require "json"
require 'digest'
require 'nokogiri'

Dir.chdir(File.dirname(__FILE__))

def hash_url(url)
	return Digest::MD5.hexdigest("#{url}")
end

def fetchContent(collectionID, xsrf="", start="")
    uri = URI('http://www.zhihu.com/collection/' + collectionID)
	response = Net::HTTP.post_form(uri, {'_xsrf' => xsrf, 'start' => start})
	begin
		json = JSON.parse(response.body)

		res = Hash.new
		res["number"] = json["msg"][0]
		res["content"] = json["msg"][1]
		res["start"] = json["msg"][2]
	rescue
		puts "parse error"
		File.open("error.log", 'w') { |file| file.write(uri.to_s + "\n" + xsrf.to_s + "\n" + start.to_s + "\n" + response.body) }
	end

    return res
end

def parseItems(src)
    items = []
    doc = Nokogiri::HTML(src)
	#File.open("article.log", 'w') { |file| file.write(src)}
    doc.css(".zm-item").each do |zitem|
        item = Hash.new
        item["title"] = zitem.css(".zm-item-title").text.strip
		
        answers = []
        zitem.css(".zm-item-fav").each do |fitem|
			answers << fitem
        end
        item["answers"] = answers
        items.push(item)
    end
	
    return items
end

def doImageCache(title, doc)
	path = "./res/#{title}_file/"
	FileUtils.mkpath(path) unless File.exists?(path)
	
	imgEntities = []
	
	doc.css("img").each do |img| 
		uri = URI.parse(img["src"])
		filename = hash_url("#{uri.to_s}") # hash url for save files
		img["src"] = "./#{title}_file/" + filename
		
		imgEntities << {'uri'=>uri, 'hash'=>filename}
	end

	imgEntities.each_slice(6).to_a.each{ |group|
		threads = []
	
		group.each {|entity|
			threads << Thread.new { 
				begin
					uri = entity['uri']
					filename = entity['hash']
					Net::HTTP.start(uri.hostname) { |http|
						resp = http.get(uri.to_s)
						File.open(path + filename, "wb") { |file|
							file.write(resp.body)
							print "."
						}
					}
				rescue
					puts "error: \n    #{uri}"
				end
			}
		}
		
		threads.each { |t| t.join }
	}

	return doc
end

def init(collectionID)
    uri = URI('http://www.zhihu.com/collection/' + collectionID)

    doc = Nokogiri::HTML(Net::HTTP.get(uri))
    xsrf = doc.css("input[name=_xsrf]")[0]["value"]

    src = Hash.new
    src["collectionName"] = doc.css("#zh-fav-head-title").text
	src["xsrf"] = xsrf
    
    return src
end

def toMultiFile(src, items)

	puts "downloading images."

    template = File.open("template.html", "r:UTF-8").read() # for Windows
    items.each{ |item| 
		buffer = ["<div><h1 class = \"title\">#{item["title"]}</h1></div>"]
        buffer.push("<div class = \"item\" id=\"wrapper\" class=\"typo typo-selection\">")
        buffer.push("<div class = \"answers\">" )
        item["answers"].each { |fitem|
		
			author = fitem.css(".zm-item-answer-author-wrap").text.strip
            content = fitem.css(".content.hidden").text
			link = "http://www.zhihu.com" + fitem.css(".answer-date-link.meta-item").attr("href")
		
			content = doImageCache("ImageCache", Nokogiri::HTML(content).css("body").children).to_html # image cache
            buffer.push("<div class = \"author\">#{author}</div>")
            buffer.push("<div class = \"content\">#{content}</div>")
			buffer.push("<div class=\"link\"><a href=\"#{link}\">[原文链接]</a></div>")
        }
        buffer.push("</div>")
        buffer.push("</div>")

		#[#{src["collectionName"].gsub(/[\x00\/\\:\*\?\"<>\|]/, "_")}]
        File.open("res/#{item["title"].gsub(/[\x00\/\\:\*\?\"<>\|]/, "_")}.html", 'w') { |file| 
            file.write(template.sub("<!-- this is template-->", buffer.join("\n")).sub!("<!-- this is title-->", item["title"])) 
        }
    }

end

collectionID = "19563328"
src = init(collectionID)
puts "collectionName : #{src["collectionName"]}\nxsrf: #{src["xsrf"]}\n"

items = []
loop do
    contents = fetchContent(collectionID, src["xsrf"], src["start"])
	#next unless contents # json parse error
    items += (parseItems(contents["content"]))
    
    puts "collection's count : #{items.size} \n"
    break if contents["start"] == -1
    src["start"] = contents["start"]
end

toMultiFile(src, items)


