# zncweather.pm v1.0 by Sven Roelse
# Copycat idea: https://github.com/DarthGandalf/znclinker

# Example: 
# !weather London,uk
# !weather New York,us
# !weather Vlissingen,nl

# 21-01-2020 - v1.0 first draft

use strict;
use warnings;
use diagnostics;
use utf8;

use JSON;
use HTTP::Response;
use POE::Component::IRC::Common;

package zncweather;
use base 'ZNC::Module';

# Please insert a valid openweathermap.org API key here!
my $owm_apikey = 'foo';

sub description {
    "Queries openweathermap.org and returns weather information."
}

sub module_types {
    $ZNC::CModInfo::NetworkModule
}

sub put_chan {
    my ($self, $chan, $msg) = @_;
    $self->PutIRC("PRIVMSG $chan :$msg");
}

sub OnChanMsg {
   # get message informations
    my ($self, $nick, $chan, $message) = @_;
    $nick = $nick->GetNick;
    $chan = $chan->GetName;

    # Strip colors and formatting
    if (POE::Component::IRC::Common::has_color($message)) {
        $message = POE::Component::IRC::Common::strip_color($message);
    }
    if (POE::Component::IRC::Common::has_formatting($message)) {
        $message = POE::Component::IRC::Common::strip_formatting($message);
    }
    if (my ($param) = $message=~/^!weather ([^,]+,[^,]{2})$/) {
        $self->CreateSocket('zncweather::owm', $param, $self->GetNetwork, $chan);
    }

    return $ZNC::CONTINUE;
}

package zncweather::owm;
use base 'ZNC::Socket';

sub Init {
    my $self = shift;
    $self->{param} = shift;
    $self->{network} = shift;
    $self->{chan} = shift;
    $self->{response} = '';
    $self->DisableReadLine;
    $self->Connect('api.openweathermap.org', 443, ssl=>1);
    $self->Write("GET https://api.openweathermap.org/data/2.5/weather?q=$self->{param}&units=metric&APPID=$owm_apikey HTTP/1.0\r\n");
    $self->Write("User-Agent: https://github.com/acvxqs/zncweather\r\n");
    $self->Write("Host: api.openweathermap.org\r\n");
    $self->Write("\r\n");
}

sub OnReadData {
    my $self = shift;
    my $data = shift;
    print "new data |$data|\n";
    $self->{response} .= $data;
}

sub OnDisconnected {
    my $self = shift;
    my $response = HTTP::Response->parse($self->{response});
    if ($response->is_success) {
        my $data = JSON->new->utf8->decode($response->decoded_content);
        $self->{network}->PutIRC("PRIVMSG $self->{chan} :City: $data->{name} · Country: $data->{sys}{country} · Weather: $data->{weather}[0]{main}/$data->{weather}[0]{description} · Temperature: $data->{main}{temp}℃ · Pressure: $data->{main}{pressure}hPa · Humidity: $data->{main}{humidity}% · Wind speed: $data->{wind}{speed}m/s · Wind degree: $data->{wind}{deg}degrees");
    } else {
        my $error = $response->status_line;
        $self->{network}->PutIRC("PRIVMSG $self->{chan} :openweathermap/$self->{param} - $error");
    }
}

sub OnTimeout {
    my $self = shift;
    $self->{network}->PutIRC("PRIVMSG $self->{chan} :openweathermap timeout");
}

sub OnConnectionRefused {
    my $self = shift;
    $self->{network}->PutIRC("PRIVMSG $self->{chan} :openweathermap connection refused");
}

1;
