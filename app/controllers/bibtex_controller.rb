
class BibtexController < ApplicationController
  before_filter :require_login

  helper :issues

  DEFAULT_LAYOUT = {  'left' => ['issuesassignedtome'], 
                      'right' => ['issuesreportedbyme'] 
                   }.freeze

  verify :xhr => true,
         :session => :page_layout,
         :only => [:add_block, :remove_block, :order_blocks]

  def index   
    @entries=BibTextile::bibdata.
      values.sort { |a,b| a['author'] <=>b['author'] }

    render :action => 'show'
  end
  
  def show
    entry=BibTextile::bibdata[params[:id]]
    if !entry
      flash[:error]="Uknown BibTeX entry '#{params[:id]}'."
      @entries=[]
    else
      @entries=[entry]
    end
  end

  def query
    begin 
      options=BibTextile.make_query(params[:id])
      @entries=BibTextile::bibdata.query(options)
    rescue => e
      flash[:error]="Invalid query '#{params[:id]}' (#{e})."
      @entries=[]
    end
    render :action => 'show'
  end

  def abstract
    entry=BibTextile::bibdata[params[:id]]
    if !entry
      flash[:error]="Uknown BibTeX entry '#{params[:id]}'."
      @entries=[]
    else
      @entries=[entry]
    end
  end
  
end
