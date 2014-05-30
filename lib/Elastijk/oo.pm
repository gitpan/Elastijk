package Elastijk::oo;
use strict;
use warnings;
use Elastijk;

sub new {
    my $class = shift;
    return bless { host => "localhost", port => "9200", @_ }, $class;
}

{
    no warnings 'redefine';
    *Elastijk::new = sub { shift; Elastijk::oo->new(@_) };
};

sub request {
    my ($self, %args) = @_;
    $args{$_} ||= $self->{$_} for grep { exists $self->{$_} } qw(host port index type);
    return Elastijk::request(\%args);
}

sub request_raw {
    my ($self, %args) = @_;
    $args{$_} ||= $self->{$_} for grep { exists $self->{$_} } qw(host port index type);
    return Elastijk::request_raw(\%args);
}

sub index {
    my ($self, %args) = @_;
    return $self->request(method => ( exists $args{id} ? "PUT" : "POST" ), %args);
}

sub get {
    my $self = shift;
    return $self->request(method => "GET", @_);
}

sub put {
    my $self = shift;
    $self->request(method => "PUT", @_);
}

sub delete {
    my $self = shift;
    return $self->request(method => "DELETE", @_);
}

sub head {
    my $self = shift;
    return $self->request(method => "HEAD", @_);
}

sub post {
    my $self = shift;
    return $self->request(method => "POST", @_);
}

sub exists {
    my $self = shift;
    my ($status,$res) = $self->request(method => "HEAD", @_);
    return ($status,'2' eq substr($status,0,1));
}

sub search {
    my $self = shift;
    return $self->request(command => "_search", method => "GET", @_);
}

sub count {
    my $self = shift;
    my ($status,$res) = $self->request(command => "_count", method => "GET", @_);
    return ($status, $res->{count});
}


sub bulk {
    my ($self, %args) = @_;
    $args{body} = join("", map { $Elastijk::JSON->encode($_)."\n" } @{$args{body}});
    my ($status,$res) = $self->request_raw(method => "POST", command => "_bulk", %args);
    $res = $Elastijk::JSON->decode($res) if $res;
    return ($status, $res);
}

sub scan_scroll {
    my ($self, %args) = @_;
    my $on_response_callback = delete $args{on_response};

    my %uri_param = %{ delete($args{uri_param}) || {} };
    $uri_param{search_type} = "scan";
    $uri_param{scroll} ||= "10m";
    my $scroll_id;
    my ($status, $res) = $self->get(%args, command => "_search", uri_param => \%uri_param);
    if (substr($status,0,1) ne '2') {
        return;
    }

    while (1) {
        $scroll_id = $res->{_scroll_id};
        ($status,$res) = $self->get(
            index => "_search", type => "scroll", #WTF
            uri_param => { scroll => $uri_param{scroll}, scroll_id => $scroll_id }
        );
        if (substr($status,0,1) eq '2' && @{$res->{hits}{hits}} > 0) {
            my $r = $on_response_callback->($status, $res);
            last if defined($r) && !$r;
            $scroll_id = $res->{_scroll_id};
        } else {
            last;
        }
    }
}

1;
