class ProjectInfo

  class ParseException < Exception; end

  attr_reader :targets, :build_configurations, :schemes

  def initialize(project_info_text)
    @project_info_text = project_info_text
    @lines = project_info_text.lines.map{|x| x.lstrip.chomp}
    @cursor = 0
    @targets = []
    @build_configurations = []
    @schemes = []

    parse
  end

  def toss(arg = nil)
    msg = "Problem parsing project info"
    if arg
      msg += ";\n#{arg}"
    end
    raise ParseException,"#{msg}\nFailed parsing:\n-------------------------------\n#{@project_info_text}"
  end

  def peek
    ret = nil
    if @cursor < @lines.size
      ret = @lines[@cursor]
      # Skip some things that we don't care about
      if ret.include?("Log record's backing file")
        @cursor += 1
        ret = peek
      end
    end
    ret
  end

  def read
    q = peek
    toss if !q
    @cursor += 1
    q
  end

  def parse
    toss if !peek || !peek.start_with?("Information about project")
    read

    while peek
      q = read
      next if q == ''
      next if q.start_with? "If no build configuration"
      if q.start_with? "Targets:"
        while peek
          y = read
          break if y == ''
          @targets << y
        end
        next
      end
      if q.start_with? "Build Configurations:"
        while peek
          y = read
          break if y == ''
          @build_configurations << y
        end
        next
      end
      if q.start_with? "Schemes:"
        while peek
          y = read
          break if y == ''
          @schemes << y
        end
        next
      end
      toss "Unknown entry: #{q}"
    end
  end
end

