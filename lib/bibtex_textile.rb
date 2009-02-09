require 'thread'
require 'erb'
require 'tempfile'
require 'pathname'
require 'bibtex.rb'

=begin
BibTeX rendering in Redcloth3/Textile.
Module basically serves for keeping the namespaces clean.
=end
module BibTextile

  module Formatter

    BIBTEX_BIBITEM_RE = /
                    !bibitem\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_BIBITEM_RE)
    
    def inline_bibitem(text)
      Bib::subs('bibitem','<p>',BIBTEX_BIBITEM_RE,text)
    end

    private :inline_bibitem


    BIBTEX_BIBTEX_RE = /
                    !bibtex\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_BIBTEX_RE)
    
    def inline_bibtex_source(text)
      Bib::subs('bibtex','<p>',BIBTEX_BIBTEX_RE,text)
    end  

    private :inline_bibtex_source
    
    
    @@lock_collect = Mutex.new
    @@collect_cite = {}

    BIBTEX_CITE_RE = /
                    !cite\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_CITE_RE)
    
    def inline_cite(text)
      text.gsub!(BIBTEX_CITE_RE) do
        begin
          all=$~
          entries=$1.split(',').map do |key|
            entry=BibTextile.bibdata[key]
            raise "unknown BibTeX entry '#{key}'" if entry.nil?             
            entry           
          end                                        
          
          n=@@lock_collect.synchronize do
            list=@@collect_cite[Thread.current] || []      
            @@collect_cite[Thread.current]=list+entries
            list.size+1
          end
          
          result='['
          entries.each_with_index do |entry,i|
            result << ('<a href="#%s"><b>%d</b></a>' % [entry['$id'],n])
            n+=1
            result << ',' if i+1<entries.size              
          end
          result << ']'
        rescue => e              
          "<div class=\"flash error\"><b>#{e}</b> near #{all}</div>"
        end
      end       
    end

    private :inline_cite


    BIBTEX_PUTBIB_RE = /
                    !putbib\{
                    ([^}]*)
                    \}  
                   /mx unless const_defined?(:BIBTEX_PUTBIB_RE)
    
    def inline_putbib(text)
      text.gsub!(BIBTEX_PUTBIB_RE) do                    
        template_id=$1.empty? ? 'putbib' : $1
        
        entries=@@lock_collect.synchronize do
          @@collect_cite.delete(Thread.current)
        end        
        
        if entries.nil? 
          '<div class="flash warning">Empty bibliography (no !cite{} for !putbib{}).</div>'
        else          
          begin
            Bib::render(template_id,entries,'<p>')
          rescue => e
            "<div class=\"flash error\"><b>#{e}</b> near putbib</div>"           
          end
        end
      end         
    end        

    private :inline_putbib

    
    BIBTEX_BIBLIOGRAPHY_RE = /
                    !bibliography\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_BIBLIOGRAPHY_RE)
    
    def inline_bibliography(text)
      Bib::subs('bibliography',:single_template,BIBTEX_BIBLIOGRAPHY_RE,text)
    end

    private :inline_bibliography

    # helpers in own namespace
    module Bib            

      # render Array entries using template_id and delimiter
      # If delimiter=:single_template the template is expected to
      # handle everything (from Array entries as input)!
      def Bib.render(template_id,entries,delimiter)
        template=BibTextile.bibtemplates[template_id]
        
        raise "missing template '#{template_id}'" if template.nil?          

        renderer=BibTeX::Renderer.new(BibTextile.bibdata)
        
        if delimiter==:single_template
          template=ERB.new(template,nil,'<>')            
          result=template.result(binding)
        else
          result=''
          entries.each_with_index do |entry,i|           
            result << renderer.html(entry,template,binding)
            result << delimiter if i+1<entries.size
          end         
        end
        result          
      end

      @@lock_query=Mutex.new

      # substitute patttern in text using render
      def Bib.subs(template_id,delimiter,pattern,text)
        text.gsub!(pattern) do
          all=$1.dup
          items=$1
          
          begin
            if items =~ /(.*)#(.*)/
                template_id,items = $1,$2
              if !BibTextile.bibtemplates.has_key?(template_id)
                raise "unknown template '#{template_id}'"
                next
              end
            end
            
            if items =~ /\=\>/              
              begin                                  
                #options=eval("{#{items}}",binding) 
                options=BibTextile.make_query(items) # less powerful but safe (w/o eval)
              rescue => e
                raise "invalid query: '#{e}'"
                next
              end
              entries=BibTextile.bibdata.query(options)
            else
              entries=items.split(',').map do |key|
                entry=BibTextile.bibdata[key]
                raise "unknown BibTeX entry '#{key}'" if entry.nil?                  
                entry
              end
            end         

            render(template_id,entries,delimiter)
            
          rescue => e
            "<div class=\"flash error\"><b>#{e}</b> near #{all}</div>"
          end                       
        end                 
      end

    end # module Bib
  end # module Formatter

  # helpers in templates
  module RendererHelpers

    # latex to html
    def l2h(text)     
      BibTeX::latex2html(t)
    end
    
    # add links to homepages for any known persons (BibTextile.homepages)
    def hp(text)
      BibTextile.link_to_hompages(l2h(text))
    end
    
    # render (partial) template
    def render(template,*entries)
      Formatter::Bib.render(template,entries,'')
    end
   
    def open_window(path,title,text,name,w=640,h=480)
      %Q[<a name="#{name}" onclick="w=window.open('#{path}', '#{title}','resizable=yes, location=no, width=#{w}, height=#{h},menubar=no, status=no, scrollbars=yes, toolbar=no'); w.focus(); return false;">
#{text}
</a>]     
    end

    # xxx link_hp, link_... xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    
  end # module RendererHelpers

  # BibTex::BibTeXData database
  def BibTextile.bibdata
    @@bibdata
  end

  # templates for rendering
  def BibTextile.bibtemplates
    @@bibtemplates
  end 

  # authors' hompages (nested Array [Regexp, homepage url])
  def BibTextile.homepages
    @@homepages
  end

  # regular extression matching any author
  def BibTextile.homepages_pattern
    @@homepages_pattern
  end

  # Generate query options (Hash) from items.
  # This is simplified but does not use eval and is hence considered safe.
  def BibTextile.make_query(items)
    result={}
    items.scan(/([^=]*)=>?([^,]*),?/) do          
      key=$1.strip
      value=$2.strip
      if (key =~ /'(.*)'/) || (key =~ /"(.*)"/)
        key=$1 
      end
      if value =~ /\/(.*)\//
        value=$1
      end
      begin
        result[key]=Regexp.new(value)
      rescue => e
        raise "failed to compile Regexp '#{value}'"
      end
    end
    result
  end

  # provide a complete list of BibTeX entries
  def BibTextile.list_bibtex_entries
    entries=@@bibdata.values.sort { |a,b| a['author'] <=>b['author'] }
    # Note: this is not the sorting we want...
    
    template=BibTextile.bibtemplates['list'] || BibTeX::Renderer::DEFAULT_TEMPLATE
    renderer=BibTeX::Renderer.new(BibTextile.bibdata)
    
    result=''
    entries.each do |entry|              
      result << renderer.html(entry,template)
      result << '<p>' # TEMPLATE
    end         
    result
  end

  # provide a list of all authors from BibTeX entries
  # Provides +name+, +firstname+, +lastname+ (html) and +author+ (LaTex),
  # where +name+ and +author+ are composed of 'firstname lastname'.      
  # +is_last+ is +true+ for the last author (delimiter)
  def BibTextile.list_bibtex_authors
    authors=BibTextile.bibdata.authors
    erb_template=BibTextile.bibtemplates['authors']
    raise %q('authors' template missing) if !erb_template
    template=ERB.new(erb_template,nil,'<>')
    result=''
    authors.each_with_index do |author,i|
      name=BibTeX.latex2html(author)
      names=name.split
      firstname=names[0..names.size-2].join(' ').strip
      lastname=names[-1].strip
      is_last=i+1<authors.size ? false : true
      result << template.result(binding)                   
    end
    result
  end

  # provide a list of all bibtex templates     
  def BibTextile.list_bibtex_templates
    result=''
    BibTextile.bibtemplates.each_pair do |key,value|
      if value =~ /\A\s*<\%#([^%]*)%>/
          info=$1.strip
      else
        info=''
      end
      result << "<b>#{key}</b> <em>#{info}</em><br>"
    end
    result
  end

  private

  def BibTextile.check_file_permissions(file)
=begin
    if (File.stat(file).mode & 037) != 0
      BibTeX::log.warn "insecure permissions for '#{file}'"
      raise "insecure permissions for '#{file}'"
    end
=end
    raise "insecure permissions for '#{file}'" if world_accessible?(file) 
    true
  end
 
  def BibTextile.world_accessible?(file)    
    Pathname.new(File.expand_path(file)).cleanpath(true).descend do |path|
      return nil if File.stat(path).mode & 007==0     
    end
    true
  end

  # read bibtext data: initalize database @@bibdata
  def BibTextile.read_bibtex_files       
    @@bibdata=BibTeX::BibTeXData.new if !defined?(@@bibdata)
    BibTeX::log.info "read_bibtex_files"  
    errors=nil
    
    src_file=File.join(File.dirname(__FILE__),'/../config/source')

    return nil if !File.exist?(src_file)
    
    begin
      BibTextile.check_file_permissions(src_file)
    rescue => e
      BibTeX::log.info "ERROR: #{e}"
      return true
    end

    IO.readlines(src_file).each do |line|
      next if line =~ /^\s*#/
        line=line.chomp.sub(/RAILS_ROOT/,RAILS_ROOT)
      BibTeX::log.info "will read from '#{line}'"  
      files=Dir.glob(line)
      files.each do |file|
        BibTeX::log.info "reading and parsing #{file}"  
        begin
          text=IO.read(file)            
          @@bibdata.scan(text,file)
        rescue => e
          BibTeX::log.info "ERROR: #{e}"
          errors||=true
        end
      end          
    end
    BibTeX::log.info "reading bbl file" 
    begin
      @@bibdata.ensure_bbl
    rescue => e
      BibTeX::log.info "ERROR: #{e}"
      errors||=true
    end
    errors
  end

  # read templates for bibtex rendering to @@bibtemplates
  def BibTextile.read_bibtex_templates
    @@bibtemplates=Hash.new if !defined?(@@bibtemplates)
    BibTeX::log.info "read_bibtex_templates"        
    
    src_path=File.join(File.dirname(__FILE__),'../config/templates/*.rhtml')
    errors=nil

    files=Dir.glob(src_path)
    files.each do |file|

      BibTeX::log.info "reading template #{file}"

      name=nil
      File.basename(file)=~/(.*)\.rhtml/ 
      name=$1 # how to do this more elegantly?

      if name.nil?
        BibTeX::log.error "PANIC"
        next
      end
      
      begin
        BibTextile.check_file_permissions(file)
      rescue => e
        BibTeX::log.info "error #{e}"  
        BibTeX::log.warn "ignoring '#{file}' (using DEFAULT_TEMPLATE"        
        @@bibtemplates[name]=BibTeX::Renderer::DEFAULT_TEMPLATE
        errors||=true
        next
      end          
      BibTeX::log.info "defined template '#{name}'"  
      text=IO.read(file)
      
      @@bibtemplates[name]=text.freeze
    end
    errors
  end

  # read authors' homepages
  def BibTextile.read_homepages     
    @@homepages=[]
    @@homepages_pattern=Regexp.union

    BibTeX::log.info "read_homepages"  
    errors=nil
    
    src_file=File.join(File.dirname(__FILE__),'/../config/homepages')

    begin
      errors||=BibTextile.read_homepage_file(src_file)      
    rescue => e      
      BibTeX::log.info "ERROR: #{e}"
      errors=true
    end

    errors
  end

  # read a single file with author/homepage mapping
  def BibTextile.read_homepage_file(fname)
    return nil if !File.exist?(fname)     

    errors=nil
   
    BibTeX::log.info "reading #{fname}"
    
    BibTextile.check_file_permissions(fname)
    
    IO.readlines(fname).each do |line|

      next if line.strip.size==0 || line=~/^#/
      
      # Do we require an "include" directive to process multiple files recursively?

      lastname,initials,url=line.split        

      begin
        rn=Regexp.new(lastname)
        ri=Regexp.new(initials)        
        raise 'invalid url' if !url =~ /^http:.*/
        r=Regexp.union(Regexp.new("(#{ri.source})[^,]+(#{rn.source})"),
                       Regexp.new("(#{rn.source})\s*,\s*(#{ri.source})"))

        @@homepages << [r,url]
        @@homepages_pattern=Regexp.union(homepages_pattern,r)
      rescue => e
        BibTeX::log.warn "'#{e}' ignoring '#{line}'"
        errors=true
      end      
    end
    errors
  end

  # read attributes to BibTex entries
  def BibTextile.read_attributes   
    BibTeX::log.info "read_attributes"        
    
    src_path=File.join(File.dirname(__FILE__),'../config/*.attr')
    errors=nil

    files=Dir.glob(src_path)
    files.each do |file|

      BibTeX::log.info "reading attributes #{file}"

      name=nil
      File.basename(file)=~/(.*)\.attr/ 
      name="$#{$1}"
      
      begin
        BibTextile.check_file_permissions(file)
        append=false
        IO.readlines(file).each do |line|
          next if line.strip.length==0 || line =~ /^#/

          if append
            value << line
          else
            raise "syntax error near '#{line}'" if !(line =~ /^([^\s]+)\s+(.*)$/)
            key=$1
            value=$2
          end
          if value =~/(.*)\\$/ 
            value=$1
            append=true
            next
          end

          entry=@@bibdata[key]
          raise "unknown entry '#{key}'" if entry.nil?        
          raise "atribute '#{name}' exists for entry '#{key}'" if entry.has_key?(name)
          entry[name]=value
          entry[name+'_src']=file
        end
      rescue => e
        BibTeX::log.info "error #{e}"  
        BibTeX::log.warn "ignoring '#{file}'"
        errors||=true
        next
      end
    end
    errors
  end
    
  public

  # initialization
  def BibTextile.initialize_bibtex_database
    BibTeX::log.info ">>> initializing BibTeXData ---"
    @@bibdata=BibTeX::BibTeXData.new
    @@bibtemplates=Hash.new
    errors=BibTextile.read_bibtex_files
    errors||=BibTextile.read_bibtex_templates
    errors||=BibTextile.read_homepages
    errors||=BibTextile.read_attributes
    if errors
      BibTeX::log.info "<<< errors while initializing BibTeXData ---"
    else
      BibTeX::log.info "<<< successfully initialized BibTeXData ---"
    end
    errors
  end
  
  # apply substitutions in text to add links to homapages
  def BibTextile.link_to_hompages(text)
    if text =~ BibTextile.homepages_pattern            
      BibTextile.homepages.each do |hp|
        pattern=hp[0]
        url=hp[1]
        if text =~ hp[0]
          matched=$&          
          text.sub!(matched,%Q(<a href="#{url}">#{matched}</a>))
        end            
      end
    end
    text
  end
  

  ::Redmine::WikiFormatting::Textile::Formatter::AUTO_LINK_RE=
  %r{
                        (                          # leading text
                          <\w+.*?>|                # leading HTML tag, or
                          [^=<>!:'"/.]|   #'       # leading punctuation, (PATCH: added '.') or            
                          ^                        # beginning of line
                        )
                        (
                          (?:https?://)|           # protocol spec, or
                          (?:s?ftps?://)|
                          (?:www\.)                # www.*
                        )
                        (
                          (\S+?)                   # url
                          (\/)?                    # slash
                        )
                        ([^\w\=\/;\(\)]*?)               # post
                        (?=<|\s|$)
    }x

  BibTeX::log.info "patched Formatter::AUTO_LINK_RE"    

end # module BibTextile



module BibTeX
  class BibTeXData
    class Entry
      # redefine bbl_html to apply BibTextile.link_to_hompages (cached)
      alias _bbl_html bbl_html
      def bbl_html
        rv=_bbl_html
        if !defined?(@bbl_substituted)
          BibTextile.link_to_hompages(rv[0])
          (2..rv.size-1).each do |i|
            if rv[i]=~/editors/
              BibTextile.link_to_hompages(rv[i])
            end
          end
          
          if self.has_key?('$download')
            rv[1]=%Q(<a href="#{self['$download']}">#{rv[1]}</a>)
          end
          @bbl_substituted=true
        end
        rv
      end
    end
  end
  class Renderer
    include BibTextile::RendererHelpers
  end
end

