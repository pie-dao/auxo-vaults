struct Config {
    address vault;
    address admin;
    address[] depositors;
}

/**
 * One depositor entered into BB
 * https://ftmscan.com/token/0xF939A5C11E6F9884D6052828981e5D95611D8b2e#balances
 * Logs:
 *   --- Simulation for Auxo  Dai Stablecoin  Vault ---
 *   vaultTokenBalancePre 4999100000000000000000 4999
 *   vaultUnderlyingBalancePre 5058167980465689726667 5058
 *   ------- EXEC BATCH BURN -------
 *
 *   Depositor 0x8f9f865Aafd6487C7aC45a22bbb9278f8fc06d47
 *   balanceOfDepositorPre 0 0
 *   balanceOfDepositorPost 5058167980465689717282 5058
 *   vaultUnderlyingBalancePost 9385 0
 *
 * Test result: ok. 1 passed; 0 failed; finished in 708.92ms
 */
function FTM_DAI() pure returns (Config memory) {
    address[] memory depositors = new address[](1);

    depositors[0] = 0x8f9f865Aafd6487C7aC45a22bbb9278f8fc06d47;

    return Config({
        vault: 0xF939A5C11E6F9884D6052828981e5D95611D8b2e,
        admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
        depositors: depositors
    });
}

/**
 * 2 depositors, entered into BB
 * https://ftmscan.com/token/0xa9dD5345ed912b359102DdD03f72738291f9f389#balances
 * Logs:
 *   --- Simulation for Auxo  Magic Internet Money  Vault ---
 *   vaultTokenBalancePre 1371027079223038426544 1371
 *   vaultUnderlyingBalancePre 1496069679064639531599 1496
 *   ------- EXEC BATCH BURN -------
 *
 *   Depositor 0x8e851e94e1667Cd76Dda1A49f258934E2BCDCF3e
 *   balanceOfDepositorPre 0 0
 *   balanceOfDepositorPost 1395409755893732356366 1395
 *   vaultUnderlyingBalancePost 100659923170907175233 100
 *
 *   Depositor 0x427197B1FB076c110f5d2bae24Fb05FED97C0456
 *   balanceOfDepositorPre 350434263626808577 0
 *   balanceOfDepositorPost 101010357434533981577 101
 *   vaultUnderlyingBalancePost 2233 0
 *
 * Test result: ok. 1 passed; 0 failed; finished in 1.35s
 */
function FTM_MIM() pure returns (Config memory) {
    address[] memory depositors = new address[](2);

    depositors[0] = 0x8e851e94e1667Cd76Dda1A49f258934E2BCDCF3e;
    depositors[1] = 0x427197B1FB076c110f5d2bae24Fb05FED97C0456;

    return Config({
        vault: 0xa9dD5345ed912b359102DdD03f72738291f9f389,
        admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
        depositors: depositors
    });
}

/**
 * 6 depositors, 3 entered into BB, 3 holding tokens
 * https://ftmscan.com/address/0x16AD251B49E62995eC6f1b6A8F48A7004666397C
 * Logs:
 *   --- Simulation for Auxo  Wrapped Fantom  Vault ---
 *   ENTERING BATCH BURN FOR ADDRESS 0x427197B1FB076c110f5d2bae24Fb05FED97C0456
 *   ENTERING BATCH BURN FOR ADDRESS 0xc15c75955f49EC15A94E041624C227211810822D
 *   ENTERING BATCH BURN FOR ADDRESS 0x1A1087Bf077f74fb21fD838a8a25Cf9Fe0818450
 *   vaultTokenBalancePre 5582047792220110752530 5582
 *   vaultUnderlyingBalancePre 5824491421101966015234 5824
 *   ------- EXEC BATCH BURN -------
 *
 *   Depositor 0x16765c8Fe6Eb838CB8f64e425b6DcCab38D4F102
 *   balanceOfDepositorPre 37704422989836809831 37
 *   balanceOfDepositorPost 141385233487652041344 141
 *   vaultUnderlyingBalancePost 5720810610604150783721 5720
 *
 *   Depositor 0x427197B1FB076c110f5d2bae24Fb05FED97C0456
 *   balanceOfDepositorPre 1000000000000000000000 1000
 *   balanceOfDepositorPost 1035231268409537131368 1035
 *   vaultUnderlyingBalancePost 5685579342194613652353 5685
 *
 *   Depositor 0xc15c75955f49EC15A94E041624C227211810822D
 *   balanceOfDepositorPre 0 0
 *   balanceOfDepositorPost 20868654794463627320 20
 *   vaultUnderlyingBalancePost 5664710687400150025033 5664
 *
 *   Depositor 0x1A1087Bf077f74fb21fD838a8a25Cf9Fe0818450
 *   balanceOfDepositorPre 8214623632792930000 8
 *   balanceOfDepositorPost 27992854888463932793 27
 *   vaultUnderlyingBalancePost 5644932456144479022240 5644
 *
 *   Depositor 0x2b285e1B49bA0cB6f71D8b0D9cAFdFBf9868fDA9
 *   balanceOfDepositorPre 0 0
 *   balanceOfDepositorPost 5168000727854528942894 5168
 *   vaultUnderlyingBalancePost 476931728289950079346 476
 *
 *   Depositor 0x8e851e94e1667Cd76Dda1A49f258934E2BCDCF3e
 *   balanceOfDepositorPre 0 0
 *   balanceOfDepositorPost 476931728289950064960 476
 *   vaultUnderlyingBalancePost 14386 0
 *
 * Test result: ok. 1 passed; 0 failed; finished in 328.35ms
 */
function FTM_WFTM() pure returns (Config memory) {
    address[] memory depositors = new address[](6);

    // entered into BB
    depositors[0] = 0x16765c8Fe6Eb838CB8f64e425b6DcCab38D4F102;
    depositors[1] = 0x2b285e1B49bA0cB6f71D8b0D9cAFdFBf9868fDA9;
    depositors[2] = 0x8e851e94e1667Cd76Dda1A49f258934E2BCDCF3e;

    // holding tokens (not entered into BB)
    depositors[3] = 0x427197B1FB076c110f5d2bae24Fb05FED97C0456;
    depositors[4] = 0xc15c75955f49EC15A94E041624C227211810822D;
    depositors[5] = 0x1A1087Bf077f74fb21fD838a8a25Cf9Fe0818450;

    return Config({
        vault: 0x16AD251B49E62995eC6f1b6A8F48A7004666397C,
        admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
        depositors: depositors
    });
}

/**
 * 3 depositors, 1 entered into BB, 2 holding tokens
 * https://ftmscan.com/address/0xBC4639e6056c299b5A957C213bcE3ea47210e2BD
 *
 * Logs:
 *   --- Simulation for Auxo  Frax  Vault ---
 *   ENTERING BATCH BURN FOR ADDRESS 0x427197B1FB076c110f5d2bae24Fb05FED97C0456
 *   ENTERING BATCH BURN FOR ADDRESS 0xe89dEe662C94FfEE76d0942f4a4bAD27cC076dd2
 *   vaultTokenBalancePre 499090588363271930266 499
 *   vaultUnderlyingBalancePre 3602747770896697469037 3602
 *   ------- EXEC BATCH BURN -------
 *   
 *   Depositor 0xB4ADB7794432dAE7E78C2258fF350fBA88250C32
 *   balanceOfDepositorPre 0 0
 *   balanceOfDepositorPost 3084353206785784292803 3084
 *   vaultUnderlyingBalancePost 518394564110913176234 518
 *   
 *   Depositor 0x427197B1FB076c110f5d2bae24Fb05FED97C0456
 *   balanceOfDepositorPre 0 0
 *   balanceOfDepositorPost 515278529209448005808 515
 *   vaultUnderlyingBalancePost 3116034901465170426 3
 *   
 *   Depositor 0xe89dEe662C94FfEE76d0942f4a4bAD27cC076dd2
 *   balanceOfDepositorPre 882349039581351889 0
 *   balanceOfDepositorPost 3998383941046517368 3
 *   vaultUnderlyingBalancePost 4947 0
 * 
 * Test result: ok. 1 passed; 0 failed; finished in 324.80ms
 */
function FTM_FRAX() pure returns (Config memory) {
    address[] memory depositors = new address[](3);

    // entered into BB
    depositors[0] = 0xB4ADB7794432dAE7E78C2258fF350fBA88250C32;

    // holding tokens (not entered into BB)
    depositors[1] = 0x427197B1FB076c110f5d2bae24Fb05FED97C0456;
    depositors[2] = 0xe89dEe662C94FfEE76d0942f4a4bAD27cC076dd2;

    return Config({
        vault: 0xBC4639e6056c299b5A957C213bcE3ea47210e2BD,
        admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
        depositors: depositors
    });
}

function FTM_USDC() pure returns (Config memory) {
    address[] memory depositors = new address[](1);

    depositors[0] = 0x8f9f865Aafd6487C7aC45a22bbb9278f8fc06d47;

    return Config({
        vault: 0x662556422AD3493fCAAc47767E8212f8C4E24513,
        admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
        depositors: depositors
    });
}
