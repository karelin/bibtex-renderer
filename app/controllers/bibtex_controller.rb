
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
    @entries=::Redmine::WikiFormatting::Textile::bibdata.
      values.sort { |a,b| a['author'] <=>b['author'] }

    render :action => 'show'
  end
  
  def show
    entry=::Redmine::WikiFormatting::Textile::bibdata[params[:id]]
    if !entry
      flash[:error]="Uknown BibTeX entry '#{params[:id]}'."
      @entries=[]
    else
      @entries=[entry]
    end
  end

  def query
    begin 
      options=::Redmine::WikiFormatting::Textile.make_query(params[:id])
      @entries=::Redmine::WikiFormatting::Textile::bibdata.query(options)
    rescue => e
      flash[:error]="Invalid query '#{params[:id]}' (#{e})."
      @entries=[]
    end
    render :action => 'show'
  end

  def abstract
    entry=::Redmine::WikiFormatting::Textile::bibdata[params[:id]]
    if !entry
      flash[:error]="Uknown BibTeX entry '#{params[:id]}'."
      @entries=[]
    else
      @entries=[entry]
    end
  end
  
end
