#!perl

use 5.010;
use strict;
use warnings;

use File::Slurp;
use Finance::Currency::Convert::KlikBCA qw(get_currencies);
use Test::More 0.98;

unless ($ENV{EXTENDED_TESTING} || $ENV{THIRD_PARTY_TESTING}) {
    plan skip_all => 'Only for extended/third-party testing';
}

my $res = get_currencies();
is($res->[0], 200, "get_currencies() succeeds")
    or diag explain $res;
exit 243 if $res->[0] == 543;

done_testing;
