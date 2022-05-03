# frozen_string_literal: true
require_relative 'job'

# source builder
class SourcerJob < JenkinsJob
  attr_reader :name
  attr_reader :basename
  attr_reader :upstream_scm
  attr_reader :type
  attr_reader :distribution
  attr_reader :packaging_scm
  attr_reader :packaging_branch
  attr_reader :downstream_triggers

  def initialize(basename, project:, type:, distribution:)
    super("#{basename}_src", 'sourcer.xml.erb')
    @name = project.name
    @basename = basename
    @upstream_scm = project.upstream_scm
    @type = type
    @distribution = distribution
    @packaging_scm = project.packaging_scm.dup
    @packaging_scm.url.gsub!('salsa.debian.org:/git/',
                             'git://salsa.debian.org/')
    @project = project
    # FIXME: why ever does the job have to do that?
    # Try the distribution specific branch name first.
    @packaging_branch = @packaging_scm.branch
    if project.series_branches.include?(@packaging_branch)
      @packaging_branch = "kubuntu_#{type}_#{distribution}"
    end

    @downstream_triggers = []
  end

  def trigger(job)
    @downstream_triggers << job.job_name
  end

  def render_packaging_scm
    scm = @project.packaging_scm_for(series: @distribution)
    PackagingSCMTemplate.new(scm: scm).render_template
  end

  def render_upstream_scm
    return '' unless @upstream_scm

    case @upstream_scm.type
    when 'git'
      render('upstream-scms/git.xml.erb')
    when 'svn'
      render('upstream-scms/svn.xml.erb')
    when 'uscan'
      ''
    when 'tarball'
      ''
    when 'bzr'
      ''
    else
      raise "Unknown upstream_scm type encountered '#{@upstream_scm.type}'"
    end
  end

  def fetch_tarball
    return '' unless @upstream_scm&.type == 'tarball'

    "if [ ! -d source ]; then
    mkdir source
    fi
    echo '#{@upstream_scm.url}' > source/url"
  end

  def fetch_bzr
    return '' unless @packaging_scm&.type == 'bzr'

    "if [ ! -d branch ]; then
    bzr branch '#{@packaging_scm.url}' branch
    else
    (cd branch &amp;&amp; bzr pull)
    fi
    # cleanup
    rm -rf packaging &amp;&amp; rm -rf source
    # seperate up packaging and source
    mkdir -p packaging/ &amp;&amp;
    cp -rf branch/debian packaging/ &amp;&amp;
    cp -rf branch source &amp;&amp;
    rm -r source/debian
    "
  end
end
