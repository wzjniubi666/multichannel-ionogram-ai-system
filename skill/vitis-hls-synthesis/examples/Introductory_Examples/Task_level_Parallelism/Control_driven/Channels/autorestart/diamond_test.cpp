

#include "diamond.h"
#include <fstream>
#include <iostream>
using namespace std;
#include "hls_task.h"
#include <ap_float.h>
using real16_T = ap_float<16,5>;

int main() {

    data_t test[N*3];
    data_t outcome[N*3];
    real16_T h = real16_T(3.14f);    // numeric conversion from float
    

    int retval = 0;
    ofstream FILE;

    // Init test vector
    for (int i = 0; i < N*3; i++) {
        test[i] = (data_t)i;
    }
    // Save the results to a file
    FILE.open("result.dat");
    hls::autorestart run_top(3, diamond, test,outcome);

        // Display the results
        for (int i = 0; i < N; i++) {
        //    cout << "Series " << iter;
            cout << " Outcome: " << (int)outcome[i] << endl;
            FILE << (int)outcome[i] << endl;
        }
        FILE.close();

    // Compare the results file with the golden results
    retval = system("diff --brief -w result.dat result.golden.dat");
    if (retval != 0) {
        cout << "Test failed  !!!" << endl;
        retval = 1;
    } else {
        cout << "Test passed !" << endl;
    }

    // Return 0 if the test passed
    return retval;
}
