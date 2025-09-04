const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');

// Initialize Firebase Admin
initializeApp();

const db = getFirestore();

async function addTestData() {
  try {
    // Add a super admin user (replace with your actual UID)
    const superAdminUid = 'F7hilhPl6wNRSftkSX6gL6J2h6n1'; // Your actual UID
    
    await db.collection('roles').doc('superadmin').collection('members').doc(superAdminUid).set({
      role: 'superadmin',
      addedAt: new Date(),
      email: 'admin@example.com'
    });
    
    console.log('✅ Added super admin user');
    
    // Add some event registrations for testing
    const eventRegistrations = [
      {
        eventId: 'weekend',
        userId: superAdminUid,
        registeredAt: new Date(),
        status: 'registered'
      },
      {
        eventId: 'weekend',
        userId: 'test-user-1',
        registeredAt: new Date(),
        status: 'registered'
      }
    ];
    
    for (const registration of eventRegistrations) {
      await db.collection('events').doc(registration.eventId).collection('registrations').doc(registration.userId).set({
        registeredAt: registration.registeredAt,
        status: registration.status
      });
    }
    
    console.log('✅ Added event registrations');
    console.log('📝 Test data added successfully!');
    console.log('🔑 Make sure to replace "your-firebase-uid-here" with your actual Firebase UID');
    
  } catch (error) {
    console.error('❌ Error adding test data:', error);
  }
}

addTestData();
