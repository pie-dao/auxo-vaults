struct Config {
    address vault;
    address admin;
    address[] depositors;
}

function FTM_DAI() pure returns (Config memory) {
    address[] memory depositors = new address[](1);

    depositors[0] = 0x8f9f865Aafd6487C7aC45a22bbb9278f8fc06d47;

    return
        Config({
            vault: 0xF939A5C11E6F9884D6052828981e5D95611D8b2e,
            admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
            depositors: depositors
        });
}

function FTM_MIM() pure returns (Config memory) {
    address[] memory depositors = new address[](2);

    depositors[0] = 0x8e851e94e1667Cd76Dda1A49f258934E2BCDCF3e;
    depositors[1] = 0x427197B1FB076c110f5d2bae24Fb05FED97C0456;

    return
        Config({
            vault: 0xa9dD5345ed912b359102DdD03f72738291f9f389,
            admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
            depositors: depositors
        });
}

function FTM_WFTM() pure returns (Config memory) {
    address[] memory depositors = new address[](6);

    depositors[0] = 0x16765c8Fe6Eb838CB8f64e425b6DcCab38D4F102;
    depositors[1] = 0x427197B1FB076c110f5d2bae24Fb05FED97C0456;
    depositors[2] = 0xc15c75955f49EC15A94E041624C227211810822D;
    depositors[3] = 0x1A1087Bf077f74fb21fD838a8a25Cf9Fe0818450;
    depositors[4] = 0x2b285e1B49bA0cB6f71D8b0D9cAFdFBf9868fDA9;
    depositors[5] = 0x8e851e94e1667Cd76Dda1A49f258934E2BCDCF3e;

    return
        Config({
            vault: 0x16AD251B49E62995eC6f1b6A8F48A7004666397C,
            admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
            depositors: depositors
        });
}

function FTM_FRAX() pure returns (Config memory) {
    address[] memory depositors = new address[](3);

    depositors[0] = 0x427197B1FB076c110f5d2bae24Fb05FED97C0456;
    depositors[1] = 0xe89dEe662C94FfEE76d0942f4a4bAD27cC076dd2;
    depositors[2] = 0xB4ADB7794432dAE7E78C2258fF350fBA88250C32;

    return
        Config({
            vault: 0xBC4639e6056c299b5A957C213bcE3ea47210e2BD,
            admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
            depositors: depositors
        });
}

function FTM_USDC() pure returns (Config memory) {
    address[] memory depositors = new address[](1);

    depositors[0] = 0x8f9f865Aafd6487C7aC45a22bbb9278f8fc06d47;

    return
        Config({
            vault: 0x662556422AD3493fCAAc47767E8212f8C4E24513,
            admin: 0x35c7C3682e5494DA5127a445ac44902059C0e268,
            depositors: depositors
        });
}
