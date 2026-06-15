# Demo Notes

This folder contains notes and links for the OL9 Image Factory demo.

## Demo Flow

1. Start SSH tunnel to OCI.
2. Open Grafana at http://127.0.0.1:3000.
3. Run local lifecycle commands:
   - build
   - split
   - deploy
   - validate
4. Show the Grafana dashboard updating.
5. Show the validation report.

## Expected Result

The final validation should show:

- Checksums match
- Zero data loss
- Zero corruption
