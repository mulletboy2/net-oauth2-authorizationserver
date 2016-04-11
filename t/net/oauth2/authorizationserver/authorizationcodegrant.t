#!perl

use strict;
use warnings;

use Test::Most;
use Test::Exception;
use Mojo::JWT;

use_ok( 'Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant' );

throws_ok(
	sub {
		Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant->new;
	},
	qr/requires either clients or overrides/,
    'constructor with no args throws'
);

my $Grant;

foreach my $with_callbacks ( 0,1 ) {

	isa_ok(
		$Grant = Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant->new(
			jwt_secret => 'Some Secret Key',
			clients    => {
				test_client => {
					client_secret => 'letmein',
					scopes => {
						eat   => 1,
						drink => 0,
						sleep => 1,
					}
				},
			},

			# am passing in a reference to the modules subs to ensure we hit
			# the code paths to call callbacks
			( $with_callbacks ? (
				verify_client_cb => sub { return Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant::_verify_client( $Grant,@_ ) },
				store_auth_code_cb => sub { return Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant::_store_auth_code( $Grant,@_ ) },
				verify_auth_code_cb => sub { return Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant::_verify_auth_code( $Grant,@_ ) },
				store_access_token_cb => sub { return Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant::_store_access_token( $Grant,@_ ) },
				verify_access_token_cb => sub { return Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant::_verify_access_token( $Grant,@_ ) },
				login_resource_owner_cb => sub { return Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant::_login_resource_owner( $Grant,@_ ) },
				confirm_by_resource_owner_cb => sub { return Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant::_confirm_by_resource_owner( $Grant,@_ ) },
			) : () ),


		),
		'Net::OAuth2::AuthorizationServer::AuthorizationCodeGrant'
	);

	run_tests( $Grant );
}

done_testing();

sub run_tests {
	my ( $Grant ) = @_;

	can_ok(
		$Grant,
		qw/
			clients
		/
	);

	ok( $Grant->login_resource_owner,'login_resource_owner' );
	ok( $Grant->confirm_by_resource_owner,'confirm_by_resource_owner' );

	note( "verify_client" );

	my %valid_client = (
		client_id => 'test_client',
		scopes    => [ qw/ eat sleep / ],
	);

	my ( $res,$error ) = $Grant->verify_client( %valid_client );

	ok( $res,'->verify_client, allowed scopes' );
	ok( ! $error,'has no error' );

	foreach my $t (
		[ { scopes => [ qw/ eat sleep drink / ] },'access_denied','disallowed scopes' ],
		[ { scopes => [ qw/ eat sleep yawn / ] },'invalid_scope','invalid scopes' ],
		[ { client_id => 'another_client' },'unauthorized_client','invalid client' ],
	) {
		( $res,$error ) = $Grant->verify_client( %valid_client,%{ $t->[0] } );

		ok( ! $res,'->verify_client, ' . $t->[2] );
		is( $error,$t->[1],'has error' );
	}

	note( "store_auth_code" );

	ok( my $auth_code = $Grant->token(
		client_id    => 'test_client',
		scopes       => [ qw/ eat sleep / ],
		type         => 'auth',
		redirect_uri => 'https://come/back',
		user_id      => 1,
	),'->token (auth code)' );

	like( $auth_code,qr/\./,'token looks like a JWT' );

	cmp_deeply(
		Mojo::JWT->new( secret => 'Some Secret Key' )->decode( $auth_code ),
		{
			'aud' => 'https://come/back',
			'client' => 'test_client',
			'exp' => ignore(),
			'iat' => ignore(),
			'jti' => ignore(),
			'scopes' => [
				'eat',
				'sleep'
			],
			'type' => 'auth',
			'user_id' => 1
		},
		'auth code decodes correctly',
	);

	ok( !$Grant->store_auth_code(
		client_id    => 'test_client',
		auth_code    => $auth_code,
		redirect_uri => 'http://come/back',
		scopes       => [ qw/ eat sleep / ],
	),'->store_auth_code (noop when ->jwt_secret set)' );

	note( "verify_auth_code" );

	my %valid_auth_code = (
		client_id     => 'test_client',
		client_secret => 'letmein',
		auth_code     => $auth_code,
		redirect_uri  => 'https://come/back',
	);

	my ( $client,$vac_error,$scopes ) = $Grant->verify_auth_code( %valid_auth_code );

	ok( $client,'->verify_auth_code, correct args' );
	ok( ! $vac_error,'has no error' );
	cmp_deeply( $scopes,[ qw/ eat sleep / ],'has scopes' );

	foreach my $t (
		[ { client_id => 'another_client' },'unauthorized_client','invalid client' ],
		[ { client_secret => 'bad secret' },'invalid_grant','bad client secret' ],
		[ { redirect_uri => 'http://not/this' },'invalid_grant','bad redirect uri' ],
	) {
		( $client,$vac_error,$scopes ) = $Grant->verify_auth_code(
			%valid_auth_code,%{ $t->[0] },
		);

		ok( ! $client,'->verify_auth_code, ' . $t->[2] );
		is( $vac_error,$t->[1],'has error' );
		ok( ! $scopes,'has no scopes' );
	}

	chop( $auth_code );

	( $client,$vac_error,$scopes ) = $Grant->verify_auth_code(
		%valid_auth_code,
		auth_code => $auth_code,
	);

	ok( ! $client,'->verify_auth_code, JWT fiddled with' );
	is( $vac_error,'invalid_grant','has error' );
	ok( ! $scopes,'has no scopes' );

	note( "store_access_token" );

	ok( my $access_token = $Grant->token(
		client_id    => 'test_client',
		scopes       => [ qw/ eat sleep / ],
		type         => 'access',
		user_id      => 1,
	),'->token (access token)' );

	ok( my $refresh_token = $Grant->token(
		client_id    => 'test_client',
		scopes       => [ qw/ eat sleep / ],
		type         => 'refresh',
		user_id      => 1,
	),'->token (refresh token)' );

	ok( !$Grant->store_access_token(
		client_id     => 'test_client',
		access_token  => $access_token,
		refresh_token => $refresh_token,
		scopes       => [ qw/ eat sleep / ],
	),'->store_auth_code (noop when ->jwt_secret set)' );

	note( "verify_access_token" );

	( $res,$error ) = $Grant->verify_access_token(
		access_token     => $access_token,
		scopes           => [ qw/ eat sleep / ],
		is_refresh_token => 0,
	);

	ok( $res,'->verify_access_token, valid access token' );
	ok( ! $error,'has no error' );

	( $res,$error ) = $Grant->verify_access_token(
		access_token     => $refresh_token,
		scopes           => [ qw/ eat sleep / ],
		is_refresh_token => 1,
	);

	ok( $res,'->verify_access_token, valid refresh token' );
	ok( ! $error,'has no error' );

	( $res,$error ) = $Grant->verify_access_token(
		access_token     => $access_token,
		scopes           => [ qw/ drink / ],
		is_refresh_token => 0,
	);

	ok( ! $res,'->verify_access_token, invalid scope' );
	is( $error,'invalid_grant','has error' );

	( $res,$error ) = $Grant->verify_access_token(
		access_token     => $access_token,
		scopes           => [ qw/ drink / ],
		is_refresh_token => 1,
	);

	ok( ! $res,'->verify_access_token, refresh token is not access token' );
	is( $error,'invalid_grant','has error' );

	( $res,$error ) = $Grant->verify_token_and_scope(
		auth_header      => "Bearer $access_token",
		scopes           => [ qw/ eat sleep / ],
		refresh_token    => 0,
	);

	ok( $res,'->verify_token_and_scope, valid access token' );
	ok( ! $error,'has no error' );

	( $res,$error ) = $Grant->verify_token_and_scope(
		auth_header   => "Bearer $access_token",
		scopes        => [ qw/ eat sleep / ],
		refresh_token => $refresh_token,
	);

	ok( $res,'->verify_token_and_scope, valid refresh token' );
	ok( ! $error,'has no error' );

	( $res,$error ) = $Grant->verify_token_and_scope(
		auth_header   => "Basic $access_token",
		scopes        => [ qw/ eat sleep / ],
		refresh_token => 0,
	);

	ok( ! $res,'->verify_token_and_scope, bad auth header' );
	is( $error,'invalid_request','has error' );

	( $res,$error ) = $Grant->verify_token_and_scope(
		auth_header   => undef,
		scopes        => [ qw/ eat sleep / ],
		refresh_token => 0,
	);

	ok( ! $res,'->verify_token_and_scope, no auth header' );
	is( $error,'invalid_request','has error' );

	chop( $access_token );

	( $res,$error ) = $Grant->verify_access_token(
		access_token     => $access_token,
		scopes           => [ qw/ eat sleep / ],
		is_refresh_token => 0,
	);

	ok( ! $res,'->verify_access_token, JWT fiddled with' );
	is( $error,'invalid_grant','has error' );
}