require 'redmine'
require 'thread'

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
                  :inline_bibitem, :inline_shortbibitem,
                  :inline_putbib
                ]+RULES

        # better insert to rules? (check for existence)

        #def to_html(*rules, &block) # replaces original version
        #  @toc = []
        #  @macros_runner = block
        #  super(*MYRULES).to_s
        #end
        
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

        # substitute patttern in text using render
        def subs(template_id,delimiter,pattern,text)
          text.gsub!(pattern) do 
            items=$1
            if items =~ /\=\>/
              options=eval("{#{items}}",binding) # Is this safe?
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

      private
      
      # read bibtext data: initalize database @@bibdata
      def Textile.read_bibtex_files
        @@bibdata=BibTeX::BibTeXData.new if !defined?(@@bibdata)
        BibTeX::log.info "read_bibtex_files"  
      
        IO.readlines("#{RAILS_ROOT}/vendor/plugins/bibtex-renderer/config/source").each do |line|
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
       
        files=Dir.glob("#{RAILS_ROOT}/vendor/plugins/bibtex-renderer/config/*.template.erb")
        files.each do |file|

          BibTeX::log.info "reading template #{file}"  
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
  end

  end # WikiFormatting  

end


