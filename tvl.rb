require 'json'
require 'optparse'

# DISCLAIMER:
# Use at your own risk. this comes with no guarantees/waranty and I am not liable for
# anything you do with this script. It is intended for good.
#
# probably against TOS/EULA or something
# highly likely this is /abusing/ this endpoint
# BUT - this will more than respect the ratelimiting implemented in the API though it
# doesnt appear to be present here.
#
# chatters != viewers, viewers can be anon and not included in chat
# tracking is not /always/ real time, this style of behavior is already seen
# in the twitch chat window itself. offlining is slightly hanlded magically as
# it seems android and some PC users flap state back to back polls frequently

# probably filled with bugs and will die silently lol

class OptParser
	def self.parse(opts)
		options = {}
		opt_parser = OptionParser.new do |opts|
			opts.banner = "Usage: tvl.rb [-u/--username <username>] [-r/--rate <seconds>] [-l/--log] "

			opts.on("-u", "--username USERNAME", "enter twitch streamer username to track") do |v|
				options[:user] = v
			end

			opts.on("-x", "--devmode", "print parsed users from each message for debugging") do |v|
				options[:devmode] = true
			end

			opts.on("-d", "--daemon", "no logging to stdout, meant for background use with -l") do |v|
				options[:daemon] = true
			end

			opts.on("-l", "--log", "log db state as json each poll to local file") do |v|
				options[:log] = true
			end

			opts.on("-v", "--verbose", "show usernames instead of just counts in stdout - non formatted, large viewer counts will be wall") do |v|
				options[:verbose] = true
			end

			opts.on("-r", "--rate INT", "int >5 in seconds for polling interval") do |v|
				begin
					options[:rate] = v.to_i
				rescue
					options[:rate] = 5
				end
			end
			opts.on("-h", "--help", "Usage: ") do
				puts opts
				exit
			end
		end

    opt_parser.parse!(opts)
		return options
	end
end

# laziest stdout filter
def log_stdout(d,nl=true)
  if !nl
    print d unless NOSTDOUT
    return nil
  end
  puts d unless NOSTDOUT
  return nil
end
@start_time = Time.now.to_i
options = OptParser.parse(ARGV)

# fields
@db ||= {
        users: {},
        count: 0
      }
USER = options[:user]
URL="https://tmi.twitch.tv/group/user/#{USER}/chatters"
COMMAND="curl -s #{URL}"
# options
VERBOSE = options[:verbose]||false
NOSTDOUT = options[:daemon]||false
DEVMODE = options[:devmode]||false
LOG = options[:log]||false
@RATE = options[:rate]
@RATE = 5 if (@RATE.nil?||@RATE<5)
# sanity checks
if USER.nil?||USER.empty?
  puts "NEED TO PASS USERNAME AS ARG"
  OptParser.parse %w[--help]
  exit 1
end
if NOSTDOUT
  if !LOG
    puts "not logging, but in daemon mode, why?"
    OptParser.parse %w[--help]
    exit 1
  end
end

# startup banner
system("clear") unless NOSTDOUT
log_stdout(%q(
 ____ ____ ____ ____ ____ ____
||T |||w |||i |||t |||c |||h ||
||__|||__|||__|||__|||__|||__||
|/__\|/__\|/__\|/__\|/__\|/__\|
 ____ ____ ____ ____ ____ ____
||V |||i |||e |||w |||e |||r ||
||__|||__|||__|||__|||__|||__||
|/__\|/__\|/__\|/__\|/__\|/__\|
 ____ ____ ____ ____ ____ ____
||L |||O |||G |||G |||E |||R ||
||__|||__|||__|||__|||__|||__||
|/__\|/__\|/__\|/__\|/__\|/__\|

Steaming pile of hot functional hacky garbage.
Built with good intentions - probably bad. Use at own risk. Written late night for fun.

Use as a streamer stats tool, mod tool, forensic tool, or anti-stream sniping tool.
It does one thing. It is intended for GOOD. Use it as you will AT YOUR OWN RISK.

Logs first seen, last seen per user, user privilage level, current state.
))
log_stdout("")
log_stdout("JSON DB LOGGING ENABLED @ #{USER}_views.log") if LOG

# new json
def get_data
 data = nil
 data = `#{COMMAND}`
 return data
end

# turn to hash
def parse_data(d)
  return '{}' if d.nil?
  begin
    JSON.parse(d)
  rescue
    '{}'
  end
end

# get data return as hash
def get_parsed_data
  d = parse_data(get_data)
  return nil if d == '{}'
  return d
end

# mark all offline, mark last seen ones as gone - will be marked online by json parsing
def cleanup_old_state
  # cleanup left users as offline
  # reverse order matters or they instantly shuffle to left :)
  @db[:users].select{|k,v| v[:status] == 'left'}.each{|k,v| v[:status] = 'offline'}
  # actually gone-enough now, youre out
  @db[:users].select{|k,v| v[:status] == 'online3'}.each{|k,v| v[:status] = 'left'}
  # strike 3
  @db[:users].select{|k,v| v[:status] == 'online2'}.each{|k,v| v[:status] = 'online3'}
  # strike 2
  @db[:users].select{|k,v| v[:status] == 'online1'}.each{|k,v| v[:status] = 'online2'}
  # missing from last poll, strike 1
  @db[:users].select{|k,v| v[:last_seen] == @last_poll}.each{|k,v| v[:status] = 'online1'}
  return nil
end

# cleanup @db,iterate over users and update state
def update_users(data)
  return nil if data.nil? || data.empty?
  cleanup_old_state
  data["chatters"].each do |role,users|
    users.each do |user|
      update_db(user,generate_user_meta(role))
      log_stdout user if DEVMODE
    end
  end
  update_count(@db[:users].select{|k,v| ['online','online1','online2','online3','new'].include?(v[:status])}.keys.uniq.count)
  return nil
end

# helper db row merger/initializer
def update_db(key,row)
  return nil if row.nil?||key.nil?
  unless @db[:users][key].nil?
    @db[:users][key] = @db[:users][key].merge(row)
  else
    @db[:users][key] = row.merge({:status => 'new', :first_seen => @this_poll})
  end
  return nil
end

# helper update viewer count
def update_count(c)
  return nil if c.nil?
  @db[:count] = c
  return nil
end

# base user meta model
# also includes first seen
# status includes
# -new
# -online
# -online1
# -online2
# -online3
# -left
# -offline
# def cleanup_old_state handles the state mgmt for online through offline
# this methed + update_db handles new -> online transition
def generate_user_meta(role)
  { :role => role, :last_seen => @this_poll, :status => 'online' }
end

# polling worker function
def poll
  updated_data = get_parsed_data
  return nil if updated_data.nil?
  update_users(updated_data)
  updated_data = nil
  stats
  return nil
end

# do the user diffs
def stats
  new = @db[:users].select{|k,v| v[:status] == 'new'}.keys
  gone = @db[:users].select{|k,v| v[:status] == 'left'}.keys
  online = @db[:users].select{|k,v| v[:status].include?('online')}.keys
  log_stdout("#{Time.now.to_s} #{new.count}/#{@db[:users].count} New Viewers") unless new.empty?
  log_stdout("#{new.sort}") if !new.empty? && VERBOSE
  log_stdout("#{Time.now.to_s} #{gone.count}/#{@db[:users].count} Missing Viewers") unless gone.empty?
  log_stdout("#{gone.sort}") if !gone.empty? && VERBOSE
  log_stdout("#{Time.now.to_s} #{online.count}/#{@db[:users].count} Stable Viewers") unless online.empty?
  log_stdout("#{online.sort}") if !online.empty? && VERBOSE
  # twitch chat list inconsistent af, their iOS app will hold presence for up to 3 min after leaving but android clients constantly flip flop from appearing and missing.
  # add some wiggle room into considering a user having left the stream
  #puts "--debugging"
  #online1 = @db[:users].select{|k,v| v[:status]== 'online1'}.keys
  #puts "#{Time.now.to_s} #{online1.count}/#{@db[:users].count} Strike 1 Gone Viewers: #{online1.sort}" unless online1.empty?
  #online2 = @db[:users].select{|k,v| v[:status]== 'online2'}.keys
  #puts "#{Time.now.to_s} #{online2.count}/#{@db[:users].count} Strike 2 Gone Viewers: #{online2.sort}" unless online2.empty?
  #online3 = @db[:users].select{|k,v| v[:status]== 'online3'}.keys
  #puts "#{Time.now.to_s} #{online3.count}/#{@db[:users].count} Strike 3 Gone Viewers: #{online3.sort}" unless online3.empty?
  return nil
end

# runner loop
def run
  setup = false
  loop do
    log_stdout ""
    @this_poll = Time.now.to_i
    poll
    if LOG
      unless setup
        File.open("#{USER}_views_#{@start_time}.log","a") do |f|
          f.write('[')
        end
        File.open("#{USER}_views_#{@start_time}.log","a") do |f|
          f.write(@db.to_json)
        end
        setup = true
      end
      File.open("#{USER}_views_#{@start_time}.log","a") do |f|
        f.write(','+@db.to_json)
      end
    end
    @last_poll = @this_poll
    log_stdout ""
    @RATE.times do
      log_stdout(".",false)
      sleep 1
    end
    log_stdout ""
  end
  return nil
end

# startup and run,
# catch ctrl-c...
begin
  run
rescue Exception => e
  if LOG
    File.open("#{USER}_views_#{@start_time}.log","a") do |f|
      f.write(']')
    end
  end
  log_stdout e
  log_stdout "Exiting..."
end
# gotta catch em all,
# ruby-mon
