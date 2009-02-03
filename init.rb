require 'redmine'
require 'thread'
require 'erb'
require 'tempfile'

# redmine/vendor/plugins/redmine_latex/init.rb

Redmine::Plugin.register :bibtex_renderer do
  name 'Redmine Bibtex plugin'
  author 'Christian Roessl'
  description 'Render Bibtex data in Wiki'
  version '0.0.1'
end

require "#{RAILS_ROOT}/lib/redmine/wiki_formatting/macros"
require "#{RAILS_ROOT}/vendor/plugins/bibtex-renderer/lib/bibtex.rb"

                      

module ::Redmine   

  module WikiFormatting  

    module Textile
      class Formatter < RedCloth3
        
        RULES = [ :inline_cite, 
                  :inline_bibitem, :inline_shortbibitem,  :inline_fancybibitem,
                  :inline_bibtex,
                  :inline_putbib
                ]+RULES

        # better insert to rules? (check for existence)
      
        
        private
        
        # render Array entries using template_id and delimiter
        def render(template_id,entries,delimiter)
          template=Textile.bibtemplates[template_id] || 
            BibTeX::Renderer::DEFAULT_TEMPLATE

          renderer=BibTeX::Renderer.new(Textile.bibdata)
            
          result=''
          entries.each_with_index do |entry,i|           
            result << renderer.html(entry,template,binding)
            result << delimiter if i+1<entries.size
          end         
          result          
        end

        @@lock_query=Mutex.new

        # Generate query options (Hash) from items.
        # This is simplified but does not use eval and is hence considered safe.
        def make_query(items)
          result={}
          items.scan(/([^=]*)=>?([^,]*),?/) do          
            key=$1.strip
            value=$2
            key=$1 if key =~ /'(.*)'/
            value=$1 if value =~ /\/(.*)\//
            result[key]=Regexp.new(value)
          end
          result
        end

        # substitute patttern in text using render
        def subs(template_id,delimiter,pattern,text)
          text.gsub!(pattern) do 
            items=$1

            if items =~ /(.*)#(.*)/
              template_id,items = $1,$2
              if !Textile.bibtemplates.has_key?(template_id)
                raise "unknown template '#{template_id}'" 
              end
            end
                     
            if items =~ /\=\>/              
              begin                                  
                #options=eval("{#{items}}",binding) 
                options=make_query(items) # less powerful but safe (w/o eval)
              rescue => e
                raise "invalid query: '#{e}'"
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

        BIBTEX_SHORTBIBITEM_RE = /
                    !shortbibitem\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_SHORTBIBITEM_RE)
        
        def inline_shortbibitem(text)
          subs('shortbibitem','<p>',BIBTEX_SHORTBIBITEM_RE,text)
        end    

        BIBTEX_FANCYBIBITEM_RE = /
                    !shortbibitem\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_FANCYBIBITEM_RE)
        
        def inline_fancybibitem(text)
          subs('fancybibitem','<p>',BIBTEX_FANCYBIBITEM_RE,text)
        end    

        BIBTEX_BIBTEX_RE = /
                    !bibtex\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_BIBTEX_RE)
        
        def inline_bibtex(text)
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

            entries= @@lock_collect.synchronize do
              @@collect_cite.delete(Thread.current)
            end        

            render(template_id,entries,'<p>')
          end
        end        


      end # Formatter

      
      def Textile.bibdata
        @@bibdata
      end
      
      def Textile.bibtemplates
        @@bibtemplates
      end

      # provide a complete list of BibTeX entries
      def Textile.list_bibtex_entries
        entries=@@bibdata.values.sort { |a,b| a['author'] <=>b['author'] }
        # Note: this is not the sorting we want...
                
        template=Textile.bibtemplates['list'] || BibTeX::Renderer.DEFAULT_TEMPLATE
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

      private
      
      # read bibtext data: initalize database @@bibdata
      def Textile.read_bibtex_files
        @@bibdata=BibTeX::BibTeXData.new if !defined?(@@bibdata)
        BibTeX::log.info "read_bibtex_files"  
                
        src_file=File.join(File.dirname(__FILE__),'/config/source')

        return if !File.exist?(src_file)
          
        if (File.stat(src_file).mode & 037) != 0
          raise "insecure permissions for '#{src_file}'"
        end

        IO.readlines(src_file).each do |line|
          line=line.chomp.sub(/RAILS_ROOT/,RAILS_ROOT)
          BibTeX::log.info "will read from '#{line}'"  
          files=Dir.glob(line)
          files.each do |file|
            BibTeX::log.info "reading and parsing #{file}"  
            text=IO.read(file)
            @@bibdata.scan(text,file)
            BibTeX::log.info "reading bbl file"             
          end          
        end
        @@bibdata.ensure_bbl
      end

      # read templates for bibtex rendering to @@bibtemplates
      def Textile.read_bibtex_templates
        @@bibtemplates=Hash.new if !defined?(@@bibtemplates)
        BibTeX::log.info "read_bibtex_templates"        
       
        src_path=File.join(File.dirname(__FILE__),'/config/*.template.erb')

        files=Dir.glob(src_path)
        files.each do |file|

          BibTeX::log.info "reading template #{file}"       
          
          if (File.stat(file).mode & 037) != 0
            BibTeX::log.warn "insecure permissions for '#{file}' (ignored)"
            next
          end
  
          text=IO.read(file)
          File.basename(file)=~/(.*)\.template\.erb/ # how to do this more elegantly?
          name=$1
          @@bibtemplates[name]=text.freeze
        end
      end

      public

      # initialization
      def Textile.initialize_bibtex_database
        @@bibdata=BibTeX::BibTeXData.new
        @@bibtemplates=Hash.new
        Textile.read_bibtex_files
        Textile.read_bibtex_templates
      end

      Textile.initialize_bibtex_database

    end # Textile

    module Macros        
      desc "Reread BibTeX database"
      macro :reread_bibtex_data do |obj,args|
        WikiFormatting::Textile.initialize_bibtex_database
        raise "<b>DONE</b>: Re-read BibTeX data. Remove macro from document."
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


