package Mojo::Webqq::Plugin::Perlcode;
use File::Temp qw/tempfile/;
use File::Path qw/mkpath rmtree/;
use POSIX qw(strftime);
BEGIN{
    eval{require BSD::Resource};
    $Mojo::Webqq::Plugin::Perlcode::is_hold_bsd_resource = 1 unless $@; 
}
use Mojo::Webqq::Run;
sub call{
    my $client = shift;
    $client->die(__PACKAGE__ . "只能运行在linux系统上") if $^O !~ /linux/; 
    $client->die(__PACKAGE__ . "依赖BSD::Resource模块，请先安装该模块") if !$Mojo::Webqq::Plugin::Perlcode::is_hold_bsd_resource; 
    $client->on(receive_message=>sub{
        my($client,$msg) = @_;
        return if not $msg->allow_plugin;
        if($msg->content=~/(?:>>>)(.*?)(?:__END__|$)/s or $msg->content =~/perl\s+-e\s+'([^']+)'/s){
            $msg->allow_plugin(0);
            my $doc = '';
            my $code = $1;
            $code=~s/^\s+|\s+$//g;
            $code=~s/CORE:://g;
            $code=~s/CORE::GLOBAL:://g; 
            return unless $code;
            $code = q#use feature qw(say);$|=1;BEGIN{use File::Path;use BSD::Resource;setrlimit(RLIMIT_NOFILE,100,100);setrlimit(RLIMIT_CPU,8,8);setrlimit(RLIMIT_FSIZE,1024,1024);setrlimit(RLIMIT_NPROC,5,5);setrlimit(RLIMIT_STACK,1024*1024*10,1024*1024*10);setrlimit(RLIMIT_DATA,1024*1024*10,1024*1024*10);*CORE::GLOBAL::fork=sub{};}$|=1;use POSIX qw(setuid setgid);{my($u,$g)= (getpwnam("nobody"))[2,3];mkpath('/tmp/webqq/bin/',{owner=>$u,group=>$g,mode=>0555}) unless -e '/tmp/webqq/bin';chdir '/tmp/webqq/bin';chroot '/tmp/webqq/bin' or die "chroot fail: $!";chdir "/";setuid($u);setgid($g);%ENV=();}# .  $code;
            my $run = Mojo::Webqq::Run->new;
            $run->log($client->log);
            my ($stdout_buf,$stderr_buf,$is_stdout_cut,$is_stderr_cut);
            $run->spawn(
                cmd          =>sub{eval $code;print STDERR $@ if $@;},
                exec_timeout => 3,
                stdout_cb => sub {
                    my ($pid, $chunk) = @_;
                    $stdout_buf.=$chunk;
                    if(length($stdout_buf) > 200){
                        $run->kill($pid);
                        $stdout_buf = substr($stdout_buf,0,200);
                        $stdout_buf .= "(已截断)";
                    }
                    elsif(count_lines($stdout_buf) > 10){
                        $run->kill($pid);
                        $stdout_buf  = join "\n",(split /\n/,$stdout_buf,11)[0..9];
                        $stdout_buf .= "(已截断)";
                    }
                },
                stderr_cb => sub {
                    my ($pid, $chunk) = @_;
                    $stderr_buf.=$chunk;
                    if(length($stderr_buf) > 500){
                        $run->kill($pid);
                        $stderr_buf = substr($stderr_buf,0,500);
                        $stderr_buf .= "(已截断)";
                    }
                    elsif(count_lines($stderr_buf) > 10){
                        $run->kill($pid);
                        $stderr_buf  = join "\n",(split /\n/,$stdout_buf,11)[0..9];
                        $stderr_buf .= "(已截断)";
                    }
                },
                exit_cb => sub {
                    my($pid,$res)=@_;
                    my $content;
                    $stderr_buf =~s/(?<=at )\(eval .+?\)(?= line)/CODE/g;
                    $stderr_buf.= "(执行超时)" if $res->{stderr}=~/\Q;Execution timeout.\E$/;
                    if(defined $stdout_buf and defined $stderr_buf){
                        if($stdout_buf=~/\n$/){$content = $stdout_buf.$stderr_buf}
                        else{$content = $stdout_buf."\n".$stderr_buf}
                    }
                    elsif(defined $stdout_buf){$content=$stdout_buf}
                    else{$content=$stderr_buf}
                    $client->reply_message($msg,$content);
                },
            );  
            $run->start;
        }    
    }); 
}

sub count_lines{
    my $data = shift;
    my $count =()=$data=~/\n/g;
    return $count++;
}

1;