require File.dirname(__FILE__) + '/lighthouse'
require 'date'

Lighthouse.account = 'YOUR_ACCOUNT'
Lighthouse.token = 'YOUR_TOKEN'

class MessageStore
  
  def initialize(project, message_title)  
    puts "initialize messageStore"
    msgs = project.messages(:q => message_title)
    if (msgs && msgs.length > 0)
      @store = msgs[0]
    else
      puts "FAIL: Could not find the message"
    end
    puts "end initialize messageStorre"  
  end
  
  def read()
    @store.body.split(">")[1].split("|")
  end
  
  def append(m)
    @store.body << "#{m}|"
    @store.save
  end
end

class Snapshot
  attr_accessor :days, :snaps_per_day
  
  def initialize(db_id)
    puts "initialize"
    @current_milestone = nil
    @project = Lighthouse::Project.find(db_id)
    if (@project.nil?)
      puts "FAIL: Cannot find bug database: #{db_id}"
      return
    end
    puts "end initialize"
  end 

  def message_store
    return @message_db unless @message_db.nil?
    @message_db = MessageStore.new(@project, "TrackerDb")    
  end
  
  # allow custom message store, just in case client doesn't like it
  def message_store=(m)
    @message_db = m
  end  
    
  def current_milestone
    return @current_milestone unless @current_milestone.nil?

    # find the milestone that ends next...    
    now = Time.now  
    current = nil  
    milestones = Lighthouse::Milestone.find(:all, :params => { :project_id => @project.id } )
    for milestone in milestones
      if (now < milestone.due_on && (current.nil? || current.due_on > milestone.due_on)) 
        current = milestone
      end
    end
    #puts "FAIL: No current milestone."
    @current_milestone = current
  end
  
  # allow custom milestone, just in case client doesn't like it
  def current_milestone=(m)
    @current_milestone = m
  end

  def query_count(q)
    total = 0
    page = 1
    begin
      rg = @project.tickets(:q => q, :page => page)
      add = rg.nil? ? 0 : rg.length
      total = total + add
      page = page + 1
    end until add == 0
    total    
  end
  
  def bug_count
    query_count("milestone:next tagged:@bug")
  end
  
  def snap
    puts "Milestone: #{self.current_milestone.title}"
    puts "Open tickets: #{self.current_milestone.open_tickets_count}"
    puts "Total tickets: #{self.current_milestone.tickets_count}"
    puts "Total Bugs: #{self.bug_count}"
    message_store.append "#{Time.now},#{current_milestone.id},#{current_milestone.open_tickets_count},#{current_milestone.tickets_count},#{bug_count}"
  end
  
  def chart
    total_snaps = days * snaps_per_day
    
    snapshots = message_store.read.select { |e| e.split(",")[1].to_i == current_milestone.id }    
    
    # plot points
    tickets_count = snapshots.map{ |e| e.split(",")[3].to_i }
    open_tickets_count = snapshots.map { |e| e.split(",")[2].to_i }
    bug_counts = snapshots.map{ |e| e.split(",")[4].to_i }
    baseline = [] # this is zero-line to get fill of bottom line 
    snapshots.length.times { |o| baseline << 0 }
     
    # post-fill (leaves the region of days left in sprint -- 13 markers for 12 days)
    snapshots.length.upto(total_snaps) do |i|
      tickets_count << -1
      open_tickets_count << -1
      bug_counts << -1
      baseline << -1
    end
    
    url = "http://chart.apis.google.com/chart?"
    url << "&chs=640x200"
    url << "&cht=lc&"
    url << "&chco=0033CC,000000,FF9900"
    url << "&chm=b,BFCFFF,0,1,0|b,BFCFFF,1,2,0|b,FFE6BF,2,3,0"
    url << "&chdl=Total|@bug|Open"
    url << "&chls=2,1,0|3,6,2|2,1,0"
    url << "&chxt=x,y"
    url << "&chma=20,20,20,20|80,20"
    url << "&chf=bg,s,F7F7F7"
    url << "&chxr=0,1,#{days}|1,0,#{tickets_count.max+20}"
    #url << "&chtt=#{@current_milestone.title}+Ticket+Count+as+of+#{Date.today}+#{Time.now.hour}:#{Time.now.min}"
    url << "&chd=t:#{tickets_count.join(',')}|#{bug_counts.join(',')}|#{open_tickets_count.join(',')}|#{baseline.join(',')}"
    url << "&chds=0,#{tickets_count.max+20}"
    
    url
  end 

end

def main
  db_id = 1 # YOUR BUG DATABASE ID
  s = Snapshot.new(db_id)
  s.days = 12
  s.snaps_per_day = 8
  s.snap
  url = s.chart
  
  base = "/srv/samba/public/projectmanagement"
  command = "rm #{base}/sprint.png && wget \"#{url}\" -O#{base}/sprint.png"
  exec command
end

main

