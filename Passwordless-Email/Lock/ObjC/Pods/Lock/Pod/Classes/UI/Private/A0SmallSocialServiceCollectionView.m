// A0SmallSocialServiceCollectionView.m
//
// Copyright (c) 2015 Auth0 (http://auth0.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "A0SmallSocialServiceCollectionView.h"

#import <libextobjc/EXTScope.h>

#import "A0ServiceCollectionViewLayoutDelegate.h"
#import "A0ServiceCollectionViewCell.h"
#import "UIFont+A0Social.h"
#import "UIButton+A0SolidButton.h"
#import "A0APIClient.h"
#import "A0Errors.h"
#import "A0IdentityProviderAuthenticator.h"
#import "A0Strategy.h"
#import "A0LockConfiguration.h"
#import "A0LockNotification.h"
#import "A0Connection.h"
#import "A0AuthParameters.h"
#import "NSObject+A0AuthenticatorProvider.h"
#import "A0Lock.h"
#import "NSError+A0APIError.h"
#import "A0ServiceViewModel.h"

#define kCellIdentifier @"ServiceCell"

@interface A0SmallSocialServiceCollectionView () <UICollectionViewDataSource>

@property (strong, nonatomic) A0LockConfiguration *configuration;
@property (strong, nonatomic) NSArray<A0ServiceViewModel *> *socialServices;
@property (strong, nonatomic) NSDictionary *serviceTheme;
@property (strong, nonatomic) A0ServiceCollectionViewLayoutDelegate *layoutDelegate;

@end

@implementation A0SmallSocialServiceCollectionView

AUTH0_DYNAMIC_LOGGER_METHODS

- (void)awakeFromNib {
    [super awakeFromNib];
    self.layoutDelegate = [[A0ServiceCollectionViewLayoutDelegate alloc] initWithServiceCount:self.socialServices.count];
    self.delegate = self.layoutDelegate;
    self.dataSource = self;
    self.scrollEnabled = self.layoutDelegate.shouldScroll;
    self.serviceTheme = [A0ServiceViewModel loadThemeInformation];
    UINib *cellNib = [UINib nibWithNibName:NSStringFromClass([A0ServiceCollectionViewCell class])
                                    bundle:[NSBundle bundleForClass:[self class]]];
    [self registerNib:cellNib forCellWithReuseIdentifier:kCellIdentifier];
}

- (void)showSocialServicesForConfiguration:(A0LockConfiguration *)configuration {
    self.configuration = configuration;
    self.socialServices = [A0ServiceViewModel servicesFromStrategies:[configuration socialStrategies]];
    [self.socialServices enumerateObjectsUsingBlock:^(A0ServiceViewModel * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj applyTheme:self.serviceTheme];
    }];
    self.layoutDelegate.serviceCount = self.socialServices.count;
    self.scrollEnabled = self.layoutDelegate.shouldScroll;
    [self reloadData];
}

- (void)triggerAuth:(UIButton *)sender {
    @weakify(self);
    A0ServiceViewModel *service = self.socialServices[sender.tag];
    NSString *connectionName = service.connection.name;
    A0APIClientAuthenticationSuccess successBlock = ^(A0UserProfile *profile, A0Token *token){
        @strongify(self);
        [self postLoginSuccessfulForConnection:service.connection];
        [self.authenticationDelegate authenticationDidEndForSocialCollectionView:self];
        [self.authenticationDelegate socialServiceCollectionView:self didAuthenticateUserWithProfile:profile token:token];
    };

    void(^failureBlock)(NSError *error) = ^(NSError *error) {
        @strongify(self);
        [self postLoginErrorNotificationWithError:error];
        [self.authenticationDelegate authenticationDidEndForSocialCollectionView:self];
        NSError *authenticationError;
        if (![error a0_cancelledSocialAuthenticationError]) {
            switch (error.code) {
                case A0ErrorCodeTwitterAppNotAuthorized:
                case A0ErrorCodeTwitterInvalidAccount:
                case A0ErrorCodeTwitterNotConfigured:
                case A0ErrorCodeAuth0NotAuthorized:
                case A0ErrorCodeAuth0InvalidConfiguration:
                case A0ErrorCodeAuth0NoURLSchemeFound:
                case A0ErrorCodeNotConnectedToInternet:
                case A0ErrorCodeGooglePlusFailed:
                    authenticationError = error;
                    break;
                default:
                    authenticationError = [A0Errors failedLoginWithConnectionName:connectionName for:error];
                    break;
            }
            [self.authenticationDelegate socialServiceCollectionView:self didFailWithError:authenticationError];
        }
    };
    [self.authenticationDelegate authenticationDidStartForSocialCollectionView:self];

    A0AuthParameters *parameters = [self.parameters copy];
    A0IdentityProviderAuthenticator *authenticator = [self a0_identityAuthenticatorFromProvider:self.lock];
    A0LogVerbose(@"Authenticating with connection %@", connectionName);
    [authenticator authenticateWithConnectionName:connectionName parameters:parameters success:successBlock failure:failureBlock];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.socialServices.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    A0ServiceCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kCellIdentifier forIndexPath:indexPath];
    A0ServiceViewModel *service = self.socialServices[indexPath.item];
    cell.serviceButton.titleLabel.font = [UIFont zocialFontOfSize:16.0f];
    [cell.serviceButton setTitleColor:service.foregroundColor forState:UIControlStateNormal];
    [cell.serviceButton setTitle:service.iconCharacter forState:UIControlStateNormal];
    [cell.serviceButton setBackgroundColor:service.backgroundColor forState:UIControlStateNormal];
    [cell.serviceButton setBackgroundColor:service.selectedBackgroundColor forState:UIControlStateHighlighted];
    [cell.serviceButton addTarget:self action:@selector(triggerAuth:) forControlEvents:UIControlEventTouchUpInside];
    cell.serviceButton.tag = indexPath.item;
    return cell;
}

#pragma mark - Lock notifications

- (void)postLoginErrorNotificationWithError:(NSError *)error {
    [[NSNotificationCenter defaultCenter] postNotificationName:A0LockNotificationLoginFailed
                                                        object:nil
                                                      userInfo:@{
                                                                 A0LockNotificationErrorParameterKey: error,
                                                                 }];
}

- (void)postLoginSuccessfulForConnection:(A0Connection *)connection {
    [[NSNotificationCenter defaultCenter] postNotificationName:A0LockNotificationLoginSuccessful
                                                        object:nil
                                                      userInfo:@{
                                                                 A0LockNotificationConnectionParameterKey: connection.name,
                                                                 }];
}
@end
