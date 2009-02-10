require 'redmine'

# redmine/vendor/plugins/bibtex_renderer/init.rb

Redmine::Plugin.register :bibtex_renderer do
  name 'Redmine Bibtex plugin'
  author 'Christian Roessl'
  description 'Render Bibtex data in Wiki'
  version '0.0.1'
end

require "#{RAILS_ROOT}/lib/redmine/wiki_formatting/macros"
require File.join(File.dirname(__FILE__),'/lib/bibtex_textile.rb')
    

module ::Redmine   

  module WikiFormatting  

    module Textile
      class Formatter < RedCloth3

        include BibTextile::Formatter
        
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
        
      end # Formatter

    end # Textile


    
    # initialization   
    BibTeX::BibTeXData.disable_predicates        # secutity issue         
    BibTeX::log.info "--- initializing bibtex-renderer ---"
    BibTextile.initialize_bibtex_database

    module Macros             
      desc "Reread BibTeX database"
      macro :reread_bibtex_data do |obj,args|
        if User.current.admin          
          rv=BibTextile.initialize_bibtex_database        
          "<div class=\"flash notice\">Re-read BibTeX data. #{rv ? '(Errors detected, see log file)' : ''}<em>Remove macro from document</em>.</div>"
        else
          "<div class=\"flash error\">Sorry, require admin status for re-reading BibTeX data.</div>"
        end
      end          

      desc "Show list of all BibTeX templates"
      macro :list_bibtex_templates do |obj,args|
        BibTextile.list_bibtex_templates
      end

      desc "Show list of all BibTeX entries"
      macro :list_bibliography do |obj,args|
        BibTextile.list_bibtex_entries
      end

      desc "Show list of all authors"
      macro :list_bibtex_authors do |obj,args|
        #args, options = extract_macro_options(args, :delimiter)
        BibTextile.list_bibtex_authors
      end
  end

  end # WikiFormatting  

end


