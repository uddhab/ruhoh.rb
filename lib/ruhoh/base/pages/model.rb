module Ruhoh::Resources::Pages
  class Model < Ruhoh::Base::Model

    FMregex = /^(---\s*\n.*?\n?)^(---\s*$\n?)/m
    DateMatcher = /^(.+\/)*(\d+-\d+-\d+)-(.*)(\.[^.]+)$/
    Matcher = /^(.+\/)*(.*)(\.[^.]+)$/

    # Process this file. See #parse_page_file
    # This model's parent collection calls #process to populate the collection.
    # Example collection dictionary:
    #   collection = { "id-1" => { <data> }, "id-2" => { <data> } }
    #
    # @returns[Hash Object] the processed data from the file.
    def process
      parsed_page = parse_page_file
      data = parsed_page['data']

      filename_data = parse_page_filename(@pointer['id'])

      data['pointer'] = @pointer
      data['id'] = @pointer['id']

      data['title'] = data['title'] || filename_data['title']
      data['date'] ||= filename_data['date'].to_s
      data['url'] = permalink(data)
      data['layout'] = collection.config['layout'] if data['layout'].nil?

      # Register this route for the previewer
      @ruhoh.routes.add(data['url'], @pointer)

      #cache
      parsed_page['data'] = data
      @ruhoh.cache.set(@pointer['realpath'], parsed_page)

      data
    end


    protected


    # Primary method to parse the file as a page-like object.
    # File API is currently defines:
    #   1. Top YAML meta-data
    #   2. Page Body
    #
    # @returns[Hash Object] processed top meta-data, raw (unconverted) content body
    def parse_page_file
      raise "File not found: #{@pointer['realpath']}" unless File.exist?(@pointer['realpath'])

      page = File.open(@pointer['realpath'], 'r:UTF-8') {|f| f.read }

      front_matter = page.match(FMregex)
      data = front_matter ?
        (YAML.load(front_matter[0].gsub(/---\n/, "")) || {}) :
        {}

      result = {
        "data" => data,
        "content" => page.gsub(FMregex, '')
      }

      # variable cache
      @data = data
      @content = result['content']

      result
    rescue Psych::SyntaxError => e
      Ruhoh.log.error("Psych::SyntaxError while parsing top YAML Metadata in #{ @pointer['realpath'] }\n" +
        "#{ e.message }\n" +
        "Try validating the YAML metadata using http://yamllint.com"
      )
      nil
    end

    def formatted_date(date)
      Time.parse(date.to_s).strftime('%Y-%m-%d') rescue false
    end

    def parse_page_filename(filename)
      data = *filename.match(DateMatcher)
      data = *filename.match(Matcher) if data.empty?
      return {} if data.empty?

      if filename =~ DateMatcher
        {
          "path" => data[1],
          "date" => data[2],
          "slug" => data[3],
          "title" => self.to_title(data[3]),
          "extension" => data[4]
        }
      else
        {
          "path" => data[1],
          "slug" => data[2],
          "title" => to_title(data[2]),
          "extension" => data[3]
        }
      end
    end

    # my-post-title ===> My Post Title
    def to_title(file_slug)
      if file_slug == 'index' && !@pointer['id'].index('/').nil?
        file_slug = @pointer['id'].split('/')[-2]
      end

      file_slug.gsub(/[^\p{Word}+]/u, ' ').gsub(/\b\w/){$&.upcase}
    end

    # Another blatently stolen method from Jekyll
    # The category is only the first one if multiple categories exist.
    def permalink(page_data)
      format = page_data['permalink'] || collection.config['permalink']
      format ||= "/:path/:filename"

      url = if format.include?(':')
        title = Ruhoh::Utils.to_url_slug(page_data['title'])
        filename = File.basename(page_data['id'])
        category = Array(page_data['categories'])[0]
        category = category.split('/').map {|c| Ruhoh::Utils.to_url_slug(c) }.join('/') if category
        relative_path = File.dirname(page_data['id'])
        relative_path = "" if relative_path == "."
        data = {
          "title"      => title,
          "filename"   => filename,
          "path"      => File.join(@pointer["resource"], relative_path),
          "relative_path" => relative_path,
          "categories" => category || '',
        }

        date = Date.parse(page_data['date']) rescue nil
        if date
          data.merge({
            "year"       => date.strftime("%Y"),
            "month"      => date.strftime("%m"),
            "day"        => date.strftime("%d"),
            "i_day"      => date.strftime("%d").to_i.to_s,
            "i_month"    => date.strftime("%m").to_i.to_s,
          })
        end

        data.inject(format) { |result, token|
          result.gsub(/:#{Regexp.escape token.first}/, token.last)
        }.gsub(/\/+/, "/")
      else
        # Use the literal permalink if it is a non-tokenized string.
        format.gsub(/^\//, '').split('/').map {|p| CGI::escape(p) }.join('/')
      end

      # Only recognize extensions registered from a 'convertable' module.
      # This means 'non-convertable' extensions should pass-through.
      if Ruhoh::Converter.extensions.include?(File.extname(url))
        url = url.gsub(%r{#{File.extname(url)}$}, '.html')
      end

      unless (page_data['permalink_ext'] || collection.config['permalink_ext'])
        url = url.gsub(/index.html$/, '').gsub(/\.html$/, '')
      end

      url = '/' if url.empty?

      @ruhoh.to_url(url)
    end
  end
end