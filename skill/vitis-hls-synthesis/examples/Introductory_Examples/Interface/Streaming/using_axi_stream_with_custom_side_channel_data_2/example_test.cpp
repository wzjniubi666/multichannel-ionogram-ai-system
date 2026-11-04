

#include "example.h"

using namespace std;

int main() {

    hls::stream<packet> A, B;
    packet tmp1, tmp2;

    for (int j = 0; j < SIZE; j++) {

        tmp1.user = j;
        if (j == 99) {
            tmp1.last = 1;
        } else {
            tmp1.last = 0;
        }

        A.write(tmp1);
        example(A, B);
        B.read(tmp2);

        if (tmp1.get_user() + 5 != tmp2.get_user()) {
            cout << "ERROR: results mismatch" << endl;
            cout << "tmp1.user=" << tmp1.get_user();
            cout << " != ";
            cout << "tmp2.user=" << tmp2.get_user() << endl;
            return 1;
        }
    }

    cout << "Success: results match" << endl;
    return 0;
}
