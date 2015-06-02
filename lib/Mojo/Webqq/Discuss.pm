package Mojo::Webqq::Discuss;
use strict;
use Mojo::Base;
use base qw(Mojo::Base Mojo::Webqq::Base);
sub has { Mojo::Base::attr(__PACKAGE__, @_) };
has [qw(
    did
    dname
    downer
)];
has member => sub{[]};

sub new {
    my $class = shift;
    my $self ;
    bless $self=@_ ? @_ > 1 ? {@_} : {%{$_[0]}} : {}, ref $class || $class;
    if(exists $self->{member} and ref $self->{member} eq "ARRAY"){
        for( @{ $self->{member} } ){
            $_ = $self->{_client}->new_discuss_member($_);
        }
    }
    $self;
}

sub search_discuss_member{
    my $self = shift;
    my %p = @_;
    if(wantarray){
        return grep {my $m = $_;(first {$p{$_} ne $m->$_} keys %p) ? 0 : 1;} @{$self->member};
    }
    else{
        return first {my $m = $_;(first {$p{$_} ne $m->$_} keys %p) ? 0 : 1;} @{$self->member};
    }
}

sub add_discuss_member{
    my $self = shift;   
    my $member = shift;
    my $nocheck = shift;
    $self->die("不支持的数据类型") if ref $member ne "Mojo::Webqq::Discuss::Member";
    if($nocheck){
        push @{$self->member},$member;
        return $self;
    }
    my $m = $self->search_discuss_member(id=>$member->id);
    if(defined $m){
        $m = $member;
    }   
    else{
        push @{$self->member},$member;
    }
    return $self;
}

sub update{
    my $self = shift;
    my $hash = shift;
    for(keys %$self){
        if($_ eq "member" and exists $hash->{member} and ref $hash->{member} eq "ARRAY"){
            my @member = map { $self->{_client}->new_discuss_member($_) } @{$hash->{member}};
            if( $self->is_empty() ){
                $self->member(\@member);
            }
            else{
                my($new_members,$lost_members)=$self->array_diff($self->member, \@member,sub{$_[0]->id});
                $self->{_client}->emit(new_discuss_member=>$_) for @{$new_members};
                $self->{_client}->emit(lose_discuss_member=>$_) for @{$lost_members};
                $self->member(\@member);
            }
        }
        else{
            $self->{$_} = $hash->{$_} if exists $hash->{$_} ;
        }
    }
    $self;
}
1;