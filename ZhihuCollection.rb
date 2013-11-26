# encoding: UTF-8
require 'fileutils'
require "net/http"
require "uri"
require "json"
require 'nokogiri'

Dir.chdir(File.dirname(__FILE__))

def fetchContent(collectionID, xsrf="", start="")
    uri = URI('http://www.zhihu.com/collection/' + collectionID)

    json = JSON.parse(Net::HTTP.post_form(uri, {'_xsrf' => xsrf, 'start' => start}).body)

    res = Hash.new
    res["number"] = json["msg"][0]
    res["content"] = json["msg"][1]
    res["start"] = json["msg"][2]
	
	#doImageCache(collectionID, Nokogiri::HTML(res["content"]))

    return res
end

def parseItems(src)
    items = []
    doc = Nokogiri::HTML(src)
    doc.css(".zm-item").each do |zitem|
        item = Hash.new
        item["title"] = zitem.css(".zm-item-title").text.strip
		
        answers = Hash.new
        zitem.css(".zm-item-fav").each do |fitem|
            answers[fitem.css(".zm-item-answer-author-wrap").text.strip] = fitem.css(".content.hidden").text
        end
        item["answers"] = answers
        items.push(item)
    end
	
    return items
end

def doImageCache(title, doc)
	path = "./res/#{title}_file/"
	FileUtils.mkpath(path) unless File.exists?(path)
	
	doc.css("img").each do |img| 
		src = img["src"]
		uri = URI.parse(src)
		filename = File.basename(uri.path)
		
		Net::HTTP.start(uri.host) { |http|
			resp = http.get(uri.path)
			open(path + filename, "wb") { |file|
				file.write(resp.body)
				puts "save: #{path + filename}"
			}
		}
		
		img["src"] = "./#{title}_file/" + filename
	end
	
	return doc
end

def init(collectionID)
    uri = URI('http://www.zhihu.com/collection/' + collectionID)

    doc = Nokogiri::HTML(Net::HTTP.get(uri))
    xsrf = doc.css("input[name=_xsrf]")[0]["value"]

    src = Hash.new
    src["collectionName"] = doc.css("#zh-fav-head-title").text
    
    return src
end

def toMultiFile(src, items)

    template = File.open("template.html", "r:UTF-8").read() # for Windows
    items.each{ |item| 
		buffer = ["<div><h1 class = \"title\">#{item["title"]}</h1></div>"]
        buffer.push("<div class = \"item\" id=\"wrapper\" class=\"typo typo-selection\">")
        buffer.push("<div class = \"answers\">" )
        item["answers"].each { |author, content|
			content = doImageCache("ImageCache", Nokogiri::HTML(content)).to_html # image cache
            buffer.push("<div class = \"author\">#{author}</div>")
            buffer.push("<div class = \"content\">#{content}</div>")
        }
        buffer.push("</div>")
        buffer.push("</div>")

		#[#{src["collectionName"].gsub(/[\x00\/\\:\*\?\"<>\|]/, "_")}]
        File.open("res/#{item["title"].gsub(/[\x00\/\\:\*\?\"<>\|]/, "_")}.html", 'w') { |file| 
            file.write(template.sub("<!-- this is template-->", buffer.join("\n")).sub!("<!-- this is title-->", item["title"])) 
        }
    }

end

def toSingleFile(src, items)

    template = File.open("template.html", "r:UTF-8").read() # for Windows
    buffer = "<div class = \"items\" id=\"wrapper\" class=\"typo typo-selection\">\n"
    items.each{ |item| 
        puts  item["title"]
        buffer += "<div class = \"item\">\n"
        buffer += "<div class = \"title\">#{item["title"]}</div>\n"
        buffer += "<div class = \"answers\">" 
        item["answers"].each { |author, content|
            buffer += "<div class = \"author\">#{author}</div>\n"
            buffer += "<div class = \"content\">#{content}</div>\n"
            buffer += "<hr />"
        }
        buffer += "</div>\n</div>\n" 
    }
    buffer += "</div>\n"
    filename = "[#{src["collectionName"].gsub(/[\x00\/\\:\*\?\"<>\|]/, "_")}].html"
    File.open(filename, 'w') { |file| 
            file.write(template.sub("<!-- this is template-->", buffer)) 
        }

end

collectionID = "19686579"

src = init(collectionID)
puts "collectionName : #{src["collectionName"]}\n"

items = []
loop do
    contents = fetchContent(collectionID, src["xsrf"], src["start"])
    items += (parseItems(contents["content"]))
    
    puts "collection's count : #{items.size} \n"
    break if contents["number"] < 20
    src["start"] = contents["start"]
end

toMultiFile(src, items)


