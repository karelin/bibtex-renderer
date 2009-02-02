require 'fileutils'
require 'tempfile'
require 'rubygems'
require 'open4' # gem
require 'logger'
require 'erb'

# parse bibtex files and render data
module BibTeX

  # --- TODO: put the following in a module

  if defined?(RAILS_ROOT)
    ROOT=RAILS_ROOT
  else
    ROOT='/tmp'
  end

  FileUtils::mkdir(File.join(ROOT, '/log')) rescue nil
  FileUtils::mkdir(File.join(ROOT, '/tmp')) rescue nil
  
  # find path to executable 
  def BibTeX.which(program)
    path=%x(which #{program}).strip
    raise "ERROR: '#{program}' not available" if path.nil? || path.length==0
    @@log.info "found '#{program}' at '#{path}'"
    path
  end

  # execute a command and raise a message on error
  def BibTeX.execute(command,desc=nil)
    @@log.info "executing #{command}"
    pid, stdin, stdout, stderr = Open4::popen4(command)
    ignored, status = Process::waitpid2(pid)
    err = stderr.readlines.join # ("\n")
    output = stdout.readlines.join
    [stdin,stdout,stderr].each{|pipe| pipe.close}
    @@log.info "status=#{status}"
    @@log.info "err=#{err}"
    @@log.info "output=#{output}"
    
    info={ 
      :desc => desc, :command => command, :status => status, 
      :stderr => err, :stdout => output 
    }
    
    if block_given?
      rv=yield info
    else
      rv=output
      raise if status.exitstatus==1
    end
    rv
  end
  
  # the bibtex log
  def BibTeX.log
    @@log
  end

  # the bibtex log
  def BibTeX.tmpdir
    @@tmpdir
  end

  # ---

  @@log=Logger.new(File.join(ROOT, '/log/bibtex.log')) 
  @@tmpdir=File.join(ROOT, '/tmp')

  RULES_LATEX2HTML = 
    [
     [ /\{([aeiouAEIOU])\}/, '\1' ],

     [ /\{\\\"([aouAOU])\}/ , '&\1uml;' ],
     [ /\\?\"([aouAOU])/ , '&\1uml;' ],
                  
     [ /\{((\\\"s)|(\\3))\}/ , '&szlig;' ],    
     [ /(\"s|\\3|\\\"s)/, '&szlig;' ],

     [ /\{\\\'([aeiouAEIOU])\}/, '&\1acute;' ],
     [ /\\?\'([aeiouAEIOU])/ , '&\1acutel;' ],
 
     [ /\{\\\^([aeiouAEIOU])\}/, '&\1circ;' ],
     [ /\\?\^([aeiouAEIOU])/ , '&\1circ;' ],
      
     [ /\{(.*)\\em\s+(.*)\}/mx, '\1<em>\2</em>' ],

     [ /([^\\])\{/, '\1'], [ /([^\\])\}/,'\1'], [/~/,' ']     
  ]

  # convert to html
  def BibTeX.latex2html(text)
    rv=text.dup
    RULES_LATEX2HTML.each do |pr|
      rv=rv.gsub(pr[0],pr[1])
    end
    rv
  end  

  RULES_LATEX2TXT = 
    [
     [ /\{([aeiouAEIOU])\}/, '\1' ],

     [ /\{\\\"([aouAOU])\}/ , '&\1e' ],
     [ /\\?\"([aouAOU])/ , '&\1e' ],
                  
     [ /\{((\\\"s)|(\\3))\}/ , 'ss;' ],    
     [ /(\"s|\\3|\\\"s)/, 'ss' ],

     [ /\{\\\'([aeiouAEIOU])\}/, '\1' ],
     [ /\\?\'([aeiouAEIOU])/ , '\1' ],
 
     [ /\{\\\^([aeiouAEIOU])\}/, '\1;' ],
     [ /\\?\^([aeiouAEIOU])/ , '\1' ],
      
     [ /\{(.*)\\em\s+(.*)\}/mx, '\1\2' ],

     [ /([^\\])\{/, '\1'], [ /([^\\])\}/,'\1'],[/~/,' ']
  ]

  # convert to ASCII text (no special characters)
  def BibTeX.latex2txt(text)
    rv=text.dup
    RULES_LATEX2TXT.each do |pr|
      rv=rv.gsub(pr[0],pr[1])
    end
    rv
  end  


  # Lexical scanner for BibTeX files (pretty general and reusable)
  class BibLex
    attr_reader :text
    attr_reader :offset, :length, :token
    
    # scan text
    def initialize(text)
      @text=text
      @len=text.length
      @head=0
      
      define_rule /\A(@[A-Za-z]+)/, :type
      
      define_rule /\A(\\\\)/, :data
      define_rule /\A(\\\")/, :data
      define_rule /\A(\\\{)/, :data
      define_rule /\A(\\\})/, :data
      define_rule /\A(\\,)/, :data
      
      define_rule /\A(\{)/, :lbrace
      define_rule /\A(\})/, :rbrace
      define_rule /\A(\")/, :quote
      define_rule /\A(,)/, :comma
      
      define_rule /\A(=)/, :equal    
      define_rule /\A([A-Za-z][A-Za-z0-9_$:]+)/, :id    
      define_rule /\A([^{}\",= ]+)/, :data
    end
    
    # a rule in BibLex
    class Rule
      # rule regexp -> token
      def initialize(regexp,token)
        @regexp=regexp
        @token=token
      end
      
      # match against input returns nil or [ token,text ]
      def match(input)
        match_data=@regexp.match(input)   
        if match_data
          [ @token, match_data[0] ]
        else
          nil
        end
      end
    end
    
    # get next token
    def next_token
      @offset=nil
      @length=nil
      @token=nil
      
      eat
      
      return :eoi if  input.nil? || input.length==0
      
      @rules.each do |r|
        m=r.match(input)
        if m
          @token=m[0]
          #puts m.inspect
          
          @offset=@head
          @length=m[1].length
          @head+=@length
          
          break
        end
      end   
      
      @token
    end
    
    # get matched text
    def token_text
      nil if @offset.nil?
      @text[@offset,@length]
    end
    
    # remaining input
    def input
      @text[@head,@len]
    end
    
    # end of input reached?
    def eoi?
      input.nil? || input.length==0
    end
    
    # define a BibLex::Rule
    def define_rule(regexp,token)
      @rules=@rules || Array.new
      @rules << Rule.new(regexp,token)
    end  
    
    private :define_rule
    
    # consume whitespace, return true/false
    def eat_whitespace
      h=@head
      @head+=1 while input=~/\A\s/
      h!=@head
    end
    
    private :eat_whitespace

    # consume BibTex comments "%...\n", return true/false
    def eat_comment
      h=@head
      @head+=$1.length while input=~/\A(%.*\n)/
      h!=@head
    end
    
    private :eat_comment
    
    # iterate eat_whitespace and eat_comment
    def eat
      while (eat_whitespace || eat_comment) do end    
    end
    
    private :eat

  end # BibLex

  # simple BibTex parser relying on BibLex
  class BibParse
    
    # BibLex object defines input, bibdata is output
    def initialize(biblex,bibtexdata)
      @lex=biblex # communication exclusively via @lookahead and self#next_token
      @output=bibtexdata
      @entry=nil
      next_token
    end
    
    # parse input
    def parse
      collection
    end
    
    protected
    
    # read next token through @lookahead (do not use @lex.next_token directly!)
    def next_token
      @lookahead=@lex.next_token
    end
    
    # return text or raise error 
    def expect(token)
      raise "expected '#{token.to_s}' got '#{@lex.token_text}'" if @lookahead!=token
      text=@lex.token_text
      next_token
      text
    end
    
    # return [token,text] or raise error 
    def expect_one_of(*token)
      token.find do |t|
        if @lookahead==t
          rval=[@lookahead,@lex.token_text]
          next_token
          return rval
        end
      end
      raise "expected one of '#{token.map { |s| s.to_s+' '}.to_s}' got '#{@lex.token_text}'"
    end
    
    # read collection
    def collection
      while record do end
    end
    
    # read record in collection
    def record
      return nil if @lookahead==:eoi
      
      offset=@lex.offset
      
      type=expect(:type).downcase
      
      expect :lbrace
      id=expect :id
      
      @entry=BibTeXData::Entry.new(id,type)
      @entry.add_field('$source_offset',offset)
      
      expect :comma
      
      datafields       
      
      expect :rbrace
      
      
      ofs=@lex.offset
      ofs=@lex.text.length if ofs.nil?
      length=ofs-offset
      @entry.add_field('$source_length',length)
      @entry.add_field('$source',@lex.text[offset,length]);
      
      @output.add @entry.dup
      @entry=nil
      
      true
    end
    
    # read datafields in record
    def datafields
      while (f=field) && @lookahead==:comma do
        @entry.add_field(f[0],f[1])
        if next_token==:rbrace
          break
        end
      end
    end
    
    # read field in datafields, return [key,data]
    def field
      key=expect :id
      key.downcase!
      
      expect :equal
      
      data=''
      
      delim=expect_one_of(:quote,:lbrace)
      
      if delim[0]==:quote
        while @lookahead!=:quote
          data+=@lex.token_text+' '
        end
      else
        n=1
        while n!=0 && @lookahead!=:eoi
          case @lookahead
          when :lbrace 
            n+=1
            data+='{'
          when :rbrace 
            n-=1
            data+='}' if n>0
          else 
            data+=@lex.token_text+' '
          end
          next_token
        end
        raise "missing '}' near '@{key}=#{data[0,20]}...}" if n>0
      end

      data=data.strip.
        gsub(/ ,/,',').gsub(/ \./,'.').gsub(/\n/,' ').gsub(/  /,' ').
        gsub(/ \{/,'{').gsub(/ \}/,'}').gsub(/\" /,'"').gsub(/ -/,'-').gsub(/ '/,'\'')   
      
      [key,data]
    end    
  end # BibParse

  
  # BibTeX database
  class BibTeXData < Hash 

    @@bibtex=BibTeX.which('bibtex')
    @@latex=BibTeX.which('latex')
    
    # BibTex entry in collection
    class Entry < Hash
      # create new entry
      def initialize(id,type,fields=nil)      
        self['$id']=id
        self['$type']=type
        if fields
          fields.each do |key,value|
            self[key]=value
          end
        end
      end
      
      # add a field
      def add_field(key,data)
        self[key]=data
      end        
      
      # restore BibTeX syntax from fields
      def to_bib
        bib="#{self['$type']}{#{self['$id']},\n"
        self.each do |key,value|         
          bib+=" #{key}={#{value}},\n" if !(key=~/\A\$/)        
        end
        bib+="}\n"
      end            

      # get author names ("firstname lastname") as array      
      def authors
        self['author'].split(' and ').map do |author| 
          author.split(',').reverse.join(' ').strip 
        end
      end           

    end # Entry    
    
    def initialize(input=nil)
      @timestamp=0
      @bbl_time=nil
      @authors=nil
      @authors_time=nil
      scan(input) if input
    end
    
    # make_bbl valled successfully and no scan or add since
    def have_bbl?
      @bbl_time==@timestamp
    end

    # ensure bbl entries are valid
    def ensure_bbl
      make_bbl if !have_bbl?
    end   

    # add data
    def scan(text)
      @timestamp+=1
      lexer=BibLex.new(text)
      parser=BibParse.new(lexer,self)
      parser.parse
    end
    
    # add an entry (called by BibParse)
    def add(entry)
      @timestamp+=1
      self[entry['$id']]=entry
    end
    
    # restore BibTeX file from fields
    def make_bibfile(filename)
      File.open(filename,'w+') do |f|
        self.each_value do |e|
          f.puts e.to_bib
        end
      end
      filename
    end
    
    # get bbl as set by bibtex
    def make_bbl(style='plain')
      @bbl_time=nil
      #`rm /tmp/bibtexdata.*`      
      FileUtils::rm Dir.glob(File.join(BibTeX.tmpdir,'bibtexdata.*'))
      froot=File.join(BibTeX.tmpdir,'bibtexdata')
      make_bibfile(froot+'.bib')
      File.open(froot+'.tex','w+') do |f|
        f.puts <<END
\\documentclass{article}
\\begin{document}
\\nocite{*}
\\bibliographystyle{#{style}}
\\bibliography{bibtexdata}
\\end{document}
END
      end

      #rv=`cd /tmp ; ( latex -halt-on-error bibtexdata &&\
      #  bibtex bibtexdata )`
      #raise "make_bbl failed: #{rv}" if $?.exitstatus!=0

      BibTeX.execute('cd %s ; %s -halt-on-error bibtexdata' % 
                     [BibTeX.tmpdir,@@latex]) do |info|
        if info[:status].exitstatus!=0
          msg="%s failed: %s" % [info[:desc],info[:stdout]]
          raise msg
        end
      end

      BibTeX.execute('cd %s ; %s bibtexdata' % [BibTeX.tmpdir,@@bibtex]) do |info|
        if info[:status].exitstatus!=0
          msg="%s failed: %s" % [info[:desc],info[:stdout]]
          raise msg
        end
      end

      bbl=IO.read(froot+'.bbl')      
      bbl.scan /^\\bibitem\{(.+)\}\n((?:(?:.+)\n)+)/ do |s| 
        id,text=$1,$2
        self[id]['$bbl']="\\bibitem{#{id}}\n#{text}"
      end
      FileUtils::rm Dir.glob(File.join(BibTeX.tmpdir,'bibtexdata.*'))

      @bbl_time=@timestamp
    end
            

    @@predicates_disabled=nil

    # disables use of predicates in query
    def BibTeXData.disable_predicates
      @@predicates_disabled=true
      @@predicates_disabled.freeze
    end
    
    # Query entries.
    # :call-seq:
    # query(options) -> Array of entries matching options
    # query(options) do |entry| ... end -> yield entries to block
    #
    # - +options+ is a Hash of fields and queried values, values are
    #   either an object responding to +:include?: or a string or 
    #   a regular expression.
    # - If given, +options[:predicate]+ is evaluated evaluate, unless
    #   disable_predicates has been called.
    # - If +options[:require]+ is given (+include?+) the respective 
    #   fields are required,
    #   the default is undefined fields pass all tests.
    # - Returns an Array which is empty if a block was given.
    def query(options)                 

      rv=[]      
      self.each_value do |entry|
        output=true

        if options.has_key?(:predicate)
          raise 'predicates are disabled' if @@predicates_disabled
          output &&= options[:predicate].call(entry)            
        end
        required=options[:require]
        
        if output
          options.each_pair do |key,value|
            field=entry[key]
            
            if required && required.include?(key)
              output &&= field
            end

            if output && field
              if value.respond_to?(:include?)                               
                output &&= value.include?(value.kind_of?(Range) ? field.to_i : field)
              elsif value.kind_of?(Regexp)
                output &&= (value =~ field.to_s)
              else
                output &&= (Regexp.new(value) =~ field.to_s)
              end
            end

            break if !output
          end # each_pair
        end
        
        if output
          if block_given?
            yield entry
          else
            rv << entry
          end     
        end
      end
      rv
    end
    
    # get index of all authors (array "firstname lastname" sorted by last word)
    def authors
      return @authors if @authors_time==@timestamp
      @authors={}
      self.each_value do |entry|
        entry.authors.each do |author|
          @authors[author]=true
        end
      end      
      @authors_time=@timestamp
      @authors=@authors.keys.sort { |a,b| a.split[-1] <=> b.split[-1] }
    end       
  
  
    #
    # apply standard sustitutions (remove fields, adapt fields)
    #
    # change type (journal, ...) // remove technical reports
    #
    # make latex include (list of publications)
    # make bbl->html (homepage) -- associate picture
    # add category   
    #     
  end # BibTexData
  

  # render BibTexData output
  class Renderer

    def initialize(bibtexdata)
      @db=bibtexdata
      @author_info = nil
      # get urls for entries
    end    

    DEFAULT_TEMPLATE=%q{
<%= bbl_authors %><br>
<em><%= bbl_title %></em><br>
<%= bbl_remainder.join("\n").gsub("/n",'<br>') %><br>
}.freeze

    # convert  netry to html musing ERB template
    # - entry a BibTeXData::Entry
    # - erb_template an ERB object or a string defining an ERB template
    # The method defines variables +bbl+, +bbl_authors+, +bbl_title+,
    # +bbl_remainder+ from +entry['$bbl'].
    def html(entry,erb_template=DEFAULT_TEMPLATE)      
      if erb_template.kind_of?(ERB)
        template=erb_template
      else       
        template=ERB.new(erb_template,nil,'<>')
      end
      if template.src =~ /bbl/
        @db.ensure_bbl
        bbl=BibTeX.latex2html(entry['$bbl'])
        bbl=bbl.sub(/^\\bibitem.*\n/,'')
        bbl=bbl.split(/\\newblock\s+/).map { |line| line.strip }
        bbl_authors=bbl[0]
        bbl_title=bbl[1]
        bbl_remainder=bbl[2,bbl.length]
      end     
      template.result(binding)
    end

  end
 

  # extensions:
  # author info -> url bbl_html includes links
  # paper/project -> url ...
  # picture ...
    
  # extra info from file (comment, picture, url)
    
  # generate index (all publications, all authors) 
  

end # BibTex


=begin

* config directory
** bib-source: paths to files
** templates as files in config directory
** generate author index
** generate key index  
* "restart" macro (nothing automatic)
* read files with additional informatik
* default links: ask google (define "person_link","title_link")

=end
