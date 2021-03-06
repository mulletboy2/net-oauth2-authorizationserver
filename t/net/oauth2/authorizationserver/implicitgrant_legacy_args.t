#!perl

use strict;
use warnings;

use Test::Most;
use Test::Exception;

use FindBin qw/ $Bin /;
use lib "$Bin";
use implicitgrant_tests;

use_ok( 'Net::OAuth2::AuthorizationServer::ImplicitGrant' );

my $Grant;

foreach my $legacy_args ( 0,1 ) {

	isa_ok(
		$Grant = Net::OAuth2::AuthorizationServer::ImplicitGrant->new(
			legacy_args => $legacy_args ? $Grant : 0,
			clients     => implicitgrant_tests::clients(),

			# am passing in a reference to the modules subs to ensure we hit
			# the code paths to call callbacks
			( $legacy_args ? (
				verify_client_cb => sub { return Net::OAuth2::AuthorizationServer::ImplicitGrant::_verify_client( shift,client_id => shift, scopes => shift, redirect_uri => shift ) },
				store_access_token_cb => sub { return Net::OAuth2::AuthorizationServer::ImplicitGrant::_store_access_token( shift,client_id => shift,auth_code => shift,access_token => shift,refresh_token => shift,expires_in => shift,scopes => shift,old_refresh_token => shift ) },
				verify_access_token_cb => sub { return Net::OAuth2::AuthorizationServer::ImplicitGrant::_verify_access_token( shift,access_token => shift,scopes => shift ) },
			) : () ), 


		),
		'Net::OAuth2::AuthorizationServer::ImplicitGrant'
	);

	implicitgrant_tests::run_tests( $Grant );
}

done_testing();
