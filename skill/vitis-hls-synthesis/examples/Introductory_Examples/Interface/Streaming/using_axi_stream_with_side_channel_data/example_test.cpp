

#include "example.h"

using namespace std;

int main() {

    hls::stream<packet> A, B;
    packet tmp1, tmp2;

    for (int j = 0; j < SIZE; j++) {

        tmp1.data = j;
        tmp1.keep = -1;
        tmp1.strb = 1;
        tmp1.user = 1;
        if (j == 99) {
            tmp1.last = 1;
        } else {
            tmp1.last = 0;
        }

        A.write(tmp1);
        example(A, B);
        B.read(tmp2);

        if (tmp1.data.to_int() + 5 != tmp2.data.to_int()) {
            cout << "ERROR: results mismatch" << endl;
            cout << "tmp1.data=" << tmp1.data;
            cout << " != ";
            cout << "tmp2.data=" << tmp2.data << endl;
            return 1;
        }
    }

    cout << "Success: results match" << endl;
    return 0;
}
