#!/bin/csh -f

setenv LANG C

set dry_run_mode = "off"
set gitrepo   = ""
set gitbranch = ""
set svnrepo   = ""
set svnbranch = ""
set commit_hash_file = ".reflection-prev_git_commit"

while ($#argv != 0)
  switch ($argv[1])
  case --dry-run:
    set dry_run_mode = "on"
    shift argv
  breaksw
  case --commit-hash-file:
  case -f:
    shift argv
    set commit_hash_file = "$argv[1]"
    shift argv
  breaksw
  case -*:
    echo "ERROR: Argument error."
    echo "ERROR: Usage: $ $0 [--dry-run] [-f(--commit-hash-file) file_name] git-repo git-branch svn-repo svn-branch"
    exit 1
  breaksw
  default:
    if ($#argv < 4) then
      echo "ERROR: Argument error."
      echo "ERROR: Usage: $ $0 [--dry-run] [-f(--commit-hash-file) file_name] git-repo git-branch svn-repo svn-branch"
      exit 1
    endif
    set i = 1
    set repo = ()
    while ($i < 5)
      switch ($argv[1])
      case -*:
        echo "ERROR: Argument error."
        echo "ERROR: Usage: $ $0 [--dry-run] [-f(--commit-hash-file) file_name] git-repo git-branch svn-repo svn-branch"
        exit 1
      breaksw
      default:
        set repo = ($repo $argv[1])
        shift argv
        @ i++
      breaksw
      endsw
    end
    set gitrepo   = $repo[1]
    set gitbranch = $repo[2]
    set svnrepo   = $repo[3]
    set svnbranch = $repo[4]
  breaksw
  endsw
end

if ($gitrepo == "" || $gitbranch == "" || $svnrepo == "" || $svnbranch == "") then
  echo "ERROR: Argument error."
  echo "ERROR: Usage: $ $0 [--dry-run] [-f(--commit-hash-file) file_name] git-repo git-branch svn-repo svn-branch"
  exit 2
endif

set datetime = `date +"%Y%m%d%H%M%S"`
set date     = `date`
set tempdir = "temp.$datetime.$$"
set diff_file = ".reflection-diff_file"

set comment_file = ".reflection-comment"

set commit_hash_temp_file = ".commit_hash_temp_file"
touch $commit_hash_file
set prev_git_commit = `cat $commit_hash_file`

echo "[git-svn-forcing-reflection]"

if ($dry_run_mode == "off") then
else
  echo "dry-running..."
endif

mkdir -p $tempdir
cd $tempdir

git clone -b $gitbranch $gitrepo git
svn checkout $svnrepo/$svnbranch svn

#
# list differ repository to svn and git.
#
diff -q -r --exclude=.git --exclude=.svn svn git >! $diff_file

#
# create operating files command and execute.
#
awk '\
  /^Only in svn/ \\
    { n = substr($3, 1, length($3)-1); \
      print "rm -fr", n "/" $4; } \
  /^Only in git/ \\
    { p = substr($3, 1, length($3)-1); \
      n = "svn" substr(p, 4); \
      print "mv -f", p "/" $4, n "/"; } \
  /^Files .* differ$/ \\
    { print "mv -f", $4 " " $2; }' \
$diff_file | csh -fx

#
# create operating svn-repository command and execute.
#
awk 'BEGIN{ print "cd svn" ;} \
  /^Only in svn/ \\
    { if (length($3) <= 4) { \
        n = ""; \
      } else { \
        n = substr($3, 5, length($3)-5) "/"; \
      } \
      print "svn del", n $4; } \
  /^Only in git/ \\
    { if (length($3) <= 4) { \
        n = ""; \
      } else { \
        n = substr($3, 5, length($3)-5) "/"; \
      } \
      print "svn add", n $4; }' \
$diff_file | csh -fx

#
# create commit logs and save current "HEAD" commit value.
#
cd git
echo "Author: git-svn-forcing-reflection" >! ../$comment_file
echo "Date: $date" >>! ../$comment_file
echo "" >>! ../$comment_file
if ($prev_git_commit == "") then
  git log --graph HEAD >>! ../$comment_file
else
  git log --graph ^${prev_git_commit} HEAD >>! ../$comment_file
endif
git log -1 --pretty=format:"%H" >! ../$commit_hash_temp_file
cd ..

#
# commit svn-repository.
#
cd svn
if ($dry_run_mode == "off") then
  setenv LANG ja_JP.UTF-8
  svn commit --file ../$comment_file
  setenv LANG C
endif

echo "Svn changes:"
svn status
echo "Svn commit message: ["
cat ../$comment_file
echo "]"
echo "Last commit hash value: [`cat ../$commit_hash_temp_file`]"
cd ..

cd ..
if ($dry_run_mode == "off") then
  mv -f $tempdir/$commit_hash_temp_file $commit_hash_file
endif
rm -fr $tempdir

echo ""
echo "git-repository: [$gitrepo/$gitbranch]"
echo "svn-repository: [$svnrepo/$svnbranch]"
echo "Reflection, OK."
