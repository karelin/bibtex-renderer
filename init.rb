require 'redmine'

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
        
        #MYRULES = [ :inline_cite, :inline_bibitem ] + RULES
        RULES = [ :inline_cite, :inline_bibitem ]+RULES
        #MYRULES = RULES

        #
        # DO WE REQUIRE AN ALIAS? -- conflicts with latex
        # 

        #def to_html(*rules, &block) # replaces original version
        #  @toc = []
        #  @macros_runner = block
        #  super(*MYRULES).to_s
        #end
        
        private

        # query

        # entry.to_bib

        BIBTEX_BIBITEM_RE = /
                    !bibitem\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_BIBITEM_RE)
        
        def inline_bibitem(text)
          text.gsub!(BIBTEX_BIBITEM_RE) do 
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

            # ... make this a function ...
            template=Textile.bibtemplates['bibitem'] || BibTeX::Renderer.DEFAULT_TEMPLATE
            renderer=BibTeX::Renderer.new(Textile.bibdata)
            
            result=''
            entries.each do |entry|              
              result << renderer.html(entry,template)
              result << '<p>' # TEMPLATE
            end         
            result
          end
        end

        BIBTEX_CITE_RE = /
                    !cite\{
                    ([^}]+)
                    \}  
                   /mx unless const_defined?(:BIBTEX_CITE_RE)
        
        def inline_cite(items)
          #raise 'not implemented'
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


