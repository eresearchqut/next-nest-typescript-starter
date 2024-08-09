'use server'

export async function apiUrl() {
   return process.env.API_URL || "http://localhost:3000"
}