package Finance::Currency::Convert::KlikBCA;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';
use LWP::Simple;
use Parse::Number::ID qw(parse_number_id);

# VERSION

our @ISA = qw(Exporter);
our @EXPORT_OK = qw(convert_currency);

our %SPEC;

$SPEC{get_currencies} = {
    summary => 'Extract data from KlikBCA page',
    v => 1.1,
};
sub get_currencies {
    my $page = get "http://www.bca.co.id/id/biaya-limit/kurs_counter_bca/kurs_counter_bca_landing.jsp"
        or return [500, "Can't retrieve KlikBCA page"];

    $page =~ s!(<table .+? DD/TT .+?</table>)!!xs
        or return [500, "Can't scrape DD/TT table"];
    my $ddtt_table = $1;
    $page =~ s!(<table .+? Bank \s Notes .+?</table>)!!xs
        or return [500, "Can't scrape Bank Notes table"];
    my $bn_table = $1;

    # XXX parse DD/TT update date
    # XXX parse Bank Notes update date

    my @items;
    while ($ddtt_table =~ m!<td[^>]+>([A-Z]{3})</td>\s+
                            <td[^>]+>([0-9.,]+)</td>\s+
                            <td[^>]+>([0-9.,]+)</td>
                           !xsg) {
        push @items, {
            currency  => $1,
            sell_ddtt => parse_number_id(text=>$2),
            buy_ddtt  => parse_number_id(text=>$3),
        };
    }
    my $num_items = @items;
    my $i = 0;
    while ($bn_table   =~ m!<td[^>]+>([0-9.,]+)</td>\s+
                            <td[^>]+>([0-9.,]+)</td>\s+</tr>
                           !xsg) {
        $items[$i]{sell_bn} = parse_number_id(text=>$1);
        $items[$i]{buy_bn}  = parse_number_id(text=>$2);
        $i++;
    }
    $i == $num_items or
        return [500, "Check: num of rows in DD/TT table != Bank Notes table"];

    my %items;
    for (@items) {
        $items{uc $_->{currency}} = $_;
        delete $_->{currency};
    }
    [200, "OK", {update_date=>undef, currencies=>\%items}];
}

sub convert_currency {
    my ($n, $from, $to) = @_;

    my $res = get_currencies();
    return undef if $res->[0] != 200;
    return undef unless uc($to) eq 'IDR';

    my $c = $res->[2]{currencies}{uc $from} or return undef;
    $n * ($c->{sell_ddtt} + $c->{buy_ddtt}) / 2;
}

1;
# ABSTRACT: Convert currencies using KlikBCA

=head1 SYNOPSIS

 use Finance::Currency::Convert::KlikBCA qw(convert_currency);

 printf "1 USD = Rp %.0f\n", convert_currency(1, 'USD', 'IDR');


=head1 TODO

=over 4

=item * Currently can only handle conversion I<to> IDR

=item * Parse last update time

=back

=head1 SEE ALSO

L<http://www.klikbca.com/>

=cut
