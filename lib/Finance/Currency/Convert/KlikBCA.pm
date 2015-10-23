package Finance::Currency::Convert::KlikBCA;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any::IfLOG '$log';
use LWP::Simple;
use Parse::Number::ID qw(parse_number_id);

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(get_currencies convert_currency);

our %SPEC;

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
    my %args = @_;

    #return [543, "Test parse failure response"];

    my $page;
    if ($args{_page_content}) {
        $page = $args{_page_content};
    } else {
        $page = get "http://www.bca.co.id/id/kurs-sukubunga/kurs_counter_bca/kurs_counter_bca_landing.jsp"
            or return [500, "Can't retrieve BCA page"];
    }

    $page =~ s!(<table .+? Mata\sUang .+?</table>)!!xs
        or return [543, "Can't scrape Mata Uang table"];
    my $mu_table = $1;
    $page =~ s!(<table .+? e-Rate .+?</table>)!!xs
        or return [543, "Can't scrape e-Rate table"];
    my $er_table = $1;
    $page =~ s!(<table .+? TT \s Counter .+?</table>)!!xs
        or return [543, "Can't scrape TT Counter table"];
    my $ttc_table = $1;
    $page =~ s!(<table .+? Bank \s Notes .+?</table>)!!xs
        or return [543, "Can't scrape e-Rate table"];
    my $bn_table = $1;

    my @items;
    while ($mu_table =~ m!<td[^>]+>([A-Z]{3})</td>!gsx) {
        push @items, { currency => $1 };
    }
    @items or return [543, "Check: no currencies found in Mata Uang Table"];
    my $num_items = @items;
    my $i;

    $num_items >= 3 or return [543, "Sanity: too few items found in Mata Uang Table"];

    $i = 0;
    while ($er_table   =~ m{
                               <td[^>]+>([0-9.,]+)</td>\s+
                               <td[^>]+>([0-9.,]+)</td>\s*
                               (?:<!--.+?-->)?\s*</tr>
                       }xsg) {
        $items[$i]{sell_er}  = parse_number_id(text=>$1);
        $items[$i]{buy_er}   = parse_number_id(text=>$2);
        $i++;
    }
    $i == $num_items or
        return [543, "Check: #rows in Mata Uang table != Bank Notes table"];

    $i = 0;
    while ($ttc_table   =~ m{
                                <td[^>]+>([0-9.,]+)</td>\s+
                                <td[^>]+>([0-9.,]+)</td>\s*
                                (?:<!--.+?-->)?\s*</tr>
                       }xsg) {
        $items[$i]{sell_ttc} = parse_number_id(text=>$1);
        $items[$i]{buy_ttc}  = parse_number_id(text=>$2);
        $i++;
    }
    $i == $num_items or
        return [543, "Check: #rows in Mata Uang table != TT Counter table"];

    $i = 0;
    while ($bn_table   =~ m{
                               <td[^>]+>([0-9.,]+)</td>\s+
                               <td[^>]+>([0-9.,]+)</td>\s*
                               (?:<!--.+?-->)?\s*</tr>
                       }xsg) {
        $items[$i]{sell_bn}  = parse_number_id(text=>$1);
        $items[$i]{buy_bn}   = parse_number_id(text=>$2);
        $i++;
    }
    $i == $num_items or
        return [543, "Check: #rows in Mata Uang table != Bank Notes table"];

    my %items;
    for (@items) {
        $items{uc $_->{currency}} = $_;
        delete $_->{currency};
    }
    [200, "OK", {update_date=>undef, currencies=>\%items}];
}

# used for testing only
our $_get_res;

$SPEC{convert_currency} = {
    v => 1.1,
    summary => 'Convert currency using KlikBCA',
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

    unless ($_get_res) {
        $_get_res = get_currencies();
        unless ($_get_res->[0] == 200) {
            warn "Can't get currencies: $_get_res->[0] - $_get_res->[1]\n";
            return undef;
        }
    }

    if (uc($to) ne 'IDR') {
        die "Currently only conversion to IDR is supported".
            " (you asked for conversion to '$to')\n";
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

 use Finance::Currency::Convert::KlikBCA qw(convert_currency);

 printf "1 USD = Rp %.0f\n", convert_currency(1, 'USD', 'IDR');


=head1 DESCRIPTION


=head1 prepend:FUNCTIONS

=head2 convert_currency($amount, $from, $to) => NUM

Currently can only handle conversion *to* IDR. Dies if given other currency.

Will warn if failed getting currencies from the webpage.

Currency rate is not cached (retrieved from the website every time). Employ your
own caching.

Currently uses the Bank Notes rate.

Will return undef if no conversion rate is available for the requested currency.

Use get_currencies(), which actually retrieves and scrapes the source web page,
if you need the more complete result.


=head1 SEE ALSO

L<http://www.klikbca.com/>

=cut
