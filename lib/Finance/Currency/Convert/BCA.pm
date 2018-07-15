package Finance::Currency::Convert::BCA;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use List::Util qw(min);

use Exporter 'import';
our @EXPORT_OK = qw(get_currencies convert_currency);

our %SPEC;

my $url = "https://www.bca.co.id/id/Individu/Sarana/Kurs-dan-Suku-Bunga/Kurs-dan-Kalkulator";

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Convert currency using BCA (Bank Central Asia)',
    description => <<"_",

This module can extract currency rates from the BCA/KlikBCA (Bank Central Asia's
internet banking) website:

    $url

Currently only conversions from a few currencies to Indonesian Rupiah (IDR) are
supported.

_
};

$SPEC{get_currencies} = {
    v => 1.1,
    summary => 'Extract data from KlikBCA/BCA page',
    result => {
        description => <<'_',
Will return a hash containing key `currencies`.

The currencies is a hash with currency symbols as keys and prices as values.

Tha values is a hash with these keys: `buy_bn` and `sell_bn` (Bank Note buy/sell
rates), `buy_er` and `sell_er` (e-Rate buy/sell rates), `buy_ttc` and `sell_ttc`
(Telegraphic Transfer Counter buy/sell rates).

_
    },
};
sub get_currencies {
    require Mojo::DOM;
    require Parse::Date::Month::ID;
    require Parse::Number::ID;
    require Time::Local;

    my %args = @_;

    #return [543, "Test parse failure response"];

    my $page;
    if ($args{_page_content}) {
        $page = $args{_page_content};
    } else {
        require Mojo::UserAgent;
        my $ua = Mojo::UserAgent->new;
        my $tx = $ua->get($url);
        unless ($tx->success) {
            my $err = $tx->error;
            return [500, "Can't retrieve URL $url: $err->{message}"];
        }
        $page = $tx->res->body;
    }

    my $dom  = Mojo::DOM->new($page);

    my %currencies;
    my $tbody = $dom->find("tbody.text-right")->[0];
    $tbody->find("tr")->each(
        sub {
            my $row0 = shift;
            my $row = $row0->find("td")->map(
                sub { $_->text })->to_array;
            #use DD; dd $row;
            return unless $row->[0] =~ /\A[A-Z]{3}\z/;
            $currencies{$row->[0]} = {
                sell_er  => Parse::Number::ID::parse_number_id(text=>$row->[1]),
                buy_er   => Parse::Number::ID::parse_number_id(text=>$row->[2]),
                sell_ttc => Parse::Number::ID::parse_number_id(text=>$row->[3]),
                buy_ttc  => Parse::Number::ID::parse_number_id(text=>$row->[4]),
                sell_bn  => Parse::Number::ID::parse_number_id(text=>$row->[5]),
                buy_bn   => Parse::Number::ID::parse_number_id(text=>$row->[6]),
            };
        }
    );

    if (keys %currencies < 3) {
        return [543, "Check: no/too few currencies found"];
    }

    my ($mtime, $mtime_er, $mtime_ttc, $mtime_bn);
  GET_MTIME_ER:
    {
        unless ($page =~ m!<th[^>]*>e-Rate\*?<br />((\d+) (\w+) (\d{4}) / (\d+):(\d+) WIB)</th>!) {
            log_warn "Cannot extract last update time for e-Rate";
            last;
        }
        my $mon = Parse::Date::Month::ID::parse_date_month_id(text=>$3) or do {
            log_warn "Cannot recognize month name '$3' in last update time '$1'";
            last;
        };
        $mtime_er = Time::Local::timegm(0, $6, $5, $2, $mon-1, $4) - 7*3600;
    }
  GET_MTIME_TTC:
    {
        unless ($page =~ m!<th[^>]*>TT Counter\*?<br />((\d+) (\w+) (\d{4}) / (\d+):(\d+) WIB)</th>!) {
            log_warn "Cannot extract last update time for TT Counter";
            last;
        }
        my $mon = Parse::Date::Month::ID::parse_date_month_id(text=>$3) or do {
            log_warn "Cannot recognize month name '$3' in last update time '$1'";
            last;
        };
        $mtime_ttc = Time::Local::timegm(0, $6, $5, $2, $mon-1, $4) - 7*3600;
    }
  GET_MTIME_BN:
    {
        unless ($page =~ m!<th[^>]*>Bank Notes\*?<br />((\d+) (\w+) (\d{4}) / (\d+):(\d+) WIB)</th>!) {
            log_warn "Cannot extract last update time for Bank Note";
            last;
        }
        my $mon = Parse::Date::Month::ID::parse_date_month_id(text=>$3) or do {
            log_warn "Cannot recognize month name '$3' in last update time '$1'";
            last;
        };
        $mtime_bn = Time::Local::timegm(0, $6, $5, $2, $mon-1, $4) - 7*3600;
    }

    $mtime = min(grep {defined} ($mtime_er, $mtime_ttc, $mtime_bn));

    [200, "OK", {
        mtime => $mtime,
        mtime_er => $mtime_er,
        mtime_ttc => $mtime_ttc,
        mtime_bn => $mtime_bn,
        currencies => \%currencies,
    }];
}

# used for testing only
our $_get_res;

$SPEC{convert_currency} = {
    v => 1.1,
    summary => 'Convert currency using BCA',
    description => <<'_',

Currently can only handle conversion `to` IDR. Dies if given other currency.

Will warn if failed getting currencies from the webpage.

Currency rate is not cached (retrieved from the website every time). Employ your
own caching.

Will return undef if no conversion rate is available for the requested currency.

Use `get_currencies()`, which actually retrieves and scrapes the source web
page, if you need the more complete result.

_
    args => {
        n => {
            schema=>'float*',
            req => 1,
            pos => 0,
        },
        from => {
            schema=>'str*',
            req => 1,
            pos => 1,
        },
        to => {
            schema=>'str*',
            req => 1,
            pos => 2,
        },
        which => {
            summary => 'Select which rate to use (default is average buy+sell for e-Rate)',
            schema => ['str*', in=>[map { my $bsa = $_; map {"${bsa}_$_"} qw(bn er ttc) } qw(buy sell avg)]],
            description => <<'_',

{buy,sell,avg}_{bn,er,ttc}.

_
            default => 'avg_er',
            pos => 3,
        },
    },
    args_as => 'array',
    result_naked => 1,
};
sub convert_currency {
    my ($n, $from, $to, $which) = @_;

    $which //= 'avg_er';

    if (uc($to) ne 'IDR') {
        die "Currently only conversion to IDR is supported".
            " (you asked for conversion to '$to')\n";
    }

    unless ($_get_res) {
        $_get_res = get_currencies();
        unless ($_get_res->[0] == 200) {
            warn "Can't get currencies: $_get_res->[0] - $_get_res->[1]\n";
            return undef;
        }
    }

    my $c = $_get_res->[2]{currencies}{uc $from} or return undef;

    my $rate;
    if ($which =~ /\Aavg_(.+)/) {
        $rate = ($c->{"buy_$1"} + $c->{"sell_$1"}) / 2;
    } else {
        $rate = $c->{$which};
    }

    $n * $rate;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

 use Finance::Currency::Convert::BCA qw(convert_currency);

 printf "1 USD = Rp %.0f\n", convert_currency(1, 'USD', 'IDR');

=cut
