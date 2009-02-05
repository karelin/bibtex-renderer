require 'redmine'
require 'thread'
require 'erb'
require 'tempfile'

# redmine/vendor/plugins/bibtex_renderer/init.rb

Redmine::Plugin.register :bibtex_renderer do
  name 'Redmine Bibtex plugin'
  author 'Christian Roessl'
  description 'Render Bibtex data in Wiki'
  version '0.0.1'
end

require "#{RAILS_ROOT}/lib/redmine/wiki_formatting/macros"
require "#{RAILS_ROOT}/vendor/plugins/bibtex-renderer/lib/bibtex.rb"

BibTeX::BibTeXData.disable_predicates                   

module ::Redmine   

  module WikiFormatting  

    module Textile
      class Formatter < RedCloth3
        
        RULES = [ :inline_bibtex ]+RULES

        BIBTEX_RULES = 
          [ :inline_bibitem,
            :inline_bibtex_source,
            :inline_cite, :inline_putbib,
            :inline_bibliography
          ]               
              
        private

        # handle BibTeX rendering
        def inline_bibtex(text)
          begin             
            BIBTEX_RULES.each do |rule|
              text=self.method(rule).call(text)
            end
          rescue => e
            text="<div class=\"flash error\">Error: #{e}</div>"
          end          
        end
        
        # render Array entries using template_id and delimiter
        # If delimiter=:single_template the template is expected to
        # handle everything (from Array entries as input)!
        def render(template_id,entries,delimiter)
          template=Textile.bibtemplates[template_id]
          
          raise "missing template '#{template_id}'" if template.nil?

          renderer=BibTeX::Renderer.new(Textile.bibdata)
                     
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
        def subs(template_id,delimiter,pattern,text)
          text.gsub!(pattern) do
            all=$1.dup
            items=$1
            
            begin
              if items =~ /(.*)#(.*)/
                  template_id,items = $1,$2
                if !Textile.bibtemplates.has_key?(template_id)
                  raise "unknown template '#{template_id}'"
                  next
                end
              end
              
              if items =~ /\=\>/              
                begin                                  
                  #options=eval("{#{items}}",binding) 
                  options=Textile.make_query(items) # less powerful but safe (w/o eval)
                rescue => e
                  raise "invalid query: '#{e}'"
                  next
                end
                entries=Textile.bibdata.query(options)
              else
                entries=items.split(',').map do |key|
                  entry=Textile.bibdata[key]
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

        BIBTEX_BIBITEM_RE = /
                    !bibitem\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_BIBITEM_RE)
        
        def inline_bibitem(text)
          subs('bibitem','<p>',BIBTEX_BIBITEM_RE,text)
        end           

        BIBTEX_BIBTEX_RE = /
                    !bibtex\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_BIBTEX_RE)
        
        def inline_bibtex_source(text)
          subs('bibtex','<p>',BIBTEX_BIBTEX_RE,text)
        end


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
                entry=Textile.bibdata[key]
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
              render(template_id,entries,'<p>')
            end
          end         
        end        

        
        BIBTEX_BIBLIOGRAPHY_RE = /
                    !bibliography\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_BIBLIOGRAPHY_RE)
        
        def inline_bibliography(text)
          subs('bibliography',:single_template,BIBTEX_BIBLIOGRAPHY_RE,text)
        end   

      end # Formatter


      def Textile.bibdata
        @@bibdata
      end
      
      def Textile.bibtemplates
        @@bibtemplates
      end  
      
      # Generate query options (Hash) from items.
      # This is simplified but does not use eval and is hence considered safe.
      def Textile.make_query(items)
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
      def Textile.list_bibtex_entries
        entries=@@bibdata.values.sort { |a,b| a['author'] <=>b['author'] }
        # Note: this is not the sorting we want...
                
        template=Textile.bibtemplates['list'] || BibTeX::Renderer::DEFAULT_TEMPLATE
        renderer=BibTeX::Renderer.new(Textile.bibdata)
            
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
      def Textile.list_bibtex_authors
        authors=Textile.bibdata.authors
        erb_template=Textile.bibtemplates['authors']
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
      def Textile.list_bibtex_templates
        result=''
        Textile.bibtemplates.each_pair do |key,value|
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
      
      def Textile.check_file_permissions(file)
        if (File.stat(file).mode & 037) != 0
          BibTeX::log.warn "insecure permissions for '#{file}'"
          raise "insecure permissions for '#{file}'"
        end
      end

      # read bibtext data: initalize database @@bibdata
      def Textile.read_bibtex_files       
        @@bibdata=BibTeX::BibTeXData.new if !defined?(@@bibdata)
        BibTeX::log.info "read_bibtex_files"  
        errors=nil
                
        src_file=File.join(File.dirname(__FILE__),'/config/source')

        return if !File.exist?(src_file)
          
        begin
          Textile.check_file_permissions(src_file)
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
      def Textile.read_bibtex_templates
        @@bibtemplates=Hash.new if !defined?(@@bibtemplates)
        BibTeX::log.info "read_bibtex_templates"        
       
        src_path=File.join(File.dirname(__FILE__),'/config/*.template.erb')
        errors=nil

        files=Dir.glob(src_path)
        files.each do |file|

          BibTeX::log.info "reading template #{file}"       
          
          begin
            Textile.check_file_permissions(file)
          rescue => e
            BibTeX::log.info "error #{e}"  
            BibTeX::log.warn "ignoring '#{file}' (using DEFAULT_TEMPLATE"
            File.basename(file)=~/(.*)\.template\.erb/ # how to do this more elegantly?
            name=$1
            @@bibtemplates[name]=BibTeX::Renderer::DEFAULT_TEMPLATE
            errors||=true
            next
          end          
  
          text=IO.read(file)
          File.basename(file)=~/(.*)\.template\.erb/ # how to do this more elegantly?
          name=$1
          @@bibtemplates[name]=text.freeze
        end
        errors
      end

      public

      # initialization
      def Textile.initialize_bibtex_database
        BibTeX::log.info "--- initializing BibTeXData ---"
        @@bibdata=BibTeX::BibTeXData.new
        @@bibtemplates=Hash.new
        errors=Textile.read_bibtex_files        
        errors||=Textile.read_bibtex_templates
      end

      BibTeX::log.info "--- initializing bibtex-renderer ---"
      Textile.initialize_bibtex_database

    end # Textile

    module Macros        
      desc "Reread BibTeX database"
      macro :reread_bibtex_data do |obj,args|
        if User.current.admin          
          rv=WikiFormatting::Textile.initialize_bibtex_database        
          "<div class=\"flash notice\">Re-read BibTeX data. #{rv ? '(Errors detected, see log file)' : ''}<em>Remove macro from document</em>.</div>"
        else
          "<div class=\"flash error\">Sorry, require admin status for re-reading BibTeX data.</div>"
        end
      end          

      desc "Show list of all BibTeX templates"
      macro :list_bibtex_templates do |obj,args|
        WikiFormatting::Textile.list_bibtex_templates
      end

      desc "Show list of all BibTeX entries"
      macro :list_bibliography do |obj,args|
        WikiFormatting::Textile.list_bibtex_entries
      end

      desc "Show list of all authors"
      macro :list_bibtex_authors do |obj,args|
        #args, options = extract_macro_options(args, :delimiter)
        WikiFormatting::Textile.list_bibtex_authors
      end
  end

  end # WikiFormatting  

end


